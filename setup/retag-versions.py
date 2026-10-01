#!/usr/bin/env python3
"""Retag a library's versioned imports from one symbol version to another.

SteamOS's Qt 6.8.0 exports a few functions PySide's wheel imports as Qt_6_PRIVATE_API
(QV4::ExecutionEngine::throwError and friends) under Qt_6 instead. Same functions, same
signatures, but the loader matches the version tag too, so libpyside6qml won't load.
This rewrites the version index of each such import in .gnu.version, and only for
symbols the provider exports under the new version and not the old one.

Usage: setup/retag-versions.py <library> <provider soname> <provider path> <from> <to>
  e.g. setup/retag-versions.py libpyside6qml.abi3.so.6.8 libQt6Qml.so.6 /usr/lib/libQt6Qml.so.6 \
         Qt_6_PRIVATE_API Qt_6
Needs pyelftools; setup/pyside-venv.sh runs it with uv run --with pyelftools.
"""
import sys

from elftools.elf.elffile import ELFFile


def exported(path):
    """{(name, version)} of a library's defined dynamic symbols."""
    with open(path, "rb") as f:
        elf = ELFFile(f)
        dynsym = elf.get_section_by_name(".dynsym")
        versym = elf.get_section_by_name(".gnu.version")
        names = {0: None, 1: None}  # local, global: unversioned
        for vd, auxs in elf.get_section_by_name(".gnu.version_d").iter_versions():
            names[vd["vd_ndx"]] = next(auxs).name
        return {(s.name, names.get(versym.get_symbol(i)["ndx"] & 0x7FFF))
                for i, s in enumerate(dynsym.iter_symbols()) if s["st_shndx"] != "SHN_UNDEF"}


def main(lib, soname, provider, old, new):
    have = exported(provider)
    with open(lib, "rb") as f:
        elf = ELFFile(f)
        dynsym = elf.get_section_by_name(".dynsym")
        versym = elf.get_section_by_name(".gnu.version")
        index = {}
        for vn, auxs in elf.get_section_by_name(".gnu.version_r").iter_versions():
            if vn.name == soname:
                index = {a.name: a["vna_other"] for a in auxs}
        if old not in index or new not in index:
            sys.exit(f"{lib} doesn't need both {old} and {new} from {soname}")
        patches = []
        for i, s in enumerate(dynsym.iter_symbols()):
            if s["st_shndx"] != "SHN_UNDEF" or versym.get_symbol(i)["ndx"] != index[old]:
                continue
            if (s.name, old) not in have and (s.name, new) in have:
                patches.append((versym["sh_offset"] + 2 * i, s.name))
    if not patches:
        print(f"{lib}: nothing to retag")
        return
    with open(lib, "r+b") as f:
        for offset, name in patches:
            f.seek(offset)
            f.write(index[new].to_bytes(2, "little" if elf.little_endian else "big"))
            print(f"{lib}: {name} {old} -> {new}")


if __name__ == "__main__":
    if len(sys.argv) != 6:
        sys.exit(__doc__)
    main(*sys.argv[1:])
