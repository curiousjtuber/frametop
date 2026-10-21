// frametop-live: the KWin side of ft-live (live/ft_live.py), the live view of the desktop's
// arrangement. ft-live loads it over D-Bus (org.kde.kwin.Scripting), the way ft-floatd loads
// frametop-float.js, and unloads it when it quits. The script changes nothing in KWin: it
// sends ft-live a snapshot (org.frametop.Live.Snapshot, a JSON string) of the outputs, the
// windows on them, the active window, and the pointer, whenever one of those changed, at
// most every 100 ms.
const SERVICE = "org.frametop.Live", PATH = "/Live", IFACE = "org.frametop.Live";
const INTERVAL = 100;

let dirty = true, last = "";
const watched = {};

function mark() { dirty = true; }
function rect(g) { return {x: g.x, y: g.y, w: g.width, h: g.height}; }

function kind(w) {
    if (w.popupWindow) return "popup";
    if (w.dialog) return "dialog";
    if (w.dock) return "dock";
    if (w.normalWindow) return "normal";
    if (w.utility || w.toolbar || w.menu) return "utility";
    return "";
}

function snapshot() {
    const outputs = [], windows = [], z = {};
    const screens = workspace.screens;
    for (let i = 0; i < screens.length; ++i)
        outputs.push({name: screens[i].name, rect: rect(screens[i].geometry), scale: screens[i].devicePixelRatio});
    const order = workspace.stackingOrder;
    for (let i = 0; i < order.length; ++i) z[String(order[i].internalId)] = i;
    const all = workspace.windowList();
    for (let i = 0; i < all.length; ++i) {
        const w = all[i], k = kind(w);
        if (!k || w.deleted || !w.managed || w.hidden || !w.output) continue;
        windows.push({
            id: String(w.internalId), caption: String(w.caption), cls: String(w.resourceClass),
            app: String(w.desktopFileName), output: w.output.name, frame: rect(w.frameGeometry),
            kind: k, parent: w.transientFor ? String(w.transientFor.internalId) : "",
            minimized: w.minimized, fullScreen: w.fullScreen, active: w.active,
            keepBelow: w.keepBelow, z: z[String(w.internalId)] === undefined ? -1 : z[String(w.internalId)]
        });
    }
    const a = workspace.activeWindow;
    return {
        outputs: outputs, windows: windows, cursor: {x: workspace.cursorPos.x, y: workspace.cursorPos.y},
        active: a ? String(a.internalId) : ""
    };
}

function watch(w) {
    const id = String(w.internalId);
    if (watched[id]) return;
    watched[id] = true;
    const signals = ["frameGeometryChanged", "outputChanged", "minimizedChanged", "captionChanged",
                     "fullScreenChanged", "activeChanged", "keepBelowChanged", "hiddenChanged"];
    for (let i = 0; i < signals.length; ++i)
        if (w[signals[i]]) w[signals[i]].connect(mark);
}

workspace.windowAdded.connect(w => { watch(w); mark(); });
workspace.windowRemoved.connect(w => { delete watched[String(w.internalId)]; mark(); });
workspace.screensChanged.connect(mark);
workspace.cursorPosChanged.connect(mark);
workspace.windowActivated.connect(mark);
if (workspace.stackingOrderChanged) workspace.stackingOrderChanged.connect(mark);
workspace.windowList().forEach(watch);

const timer = new QTimer();
timer.interval = INTERVAL;
timer.timeout.connect(() => {
    if (!dirty) return;
    dirty = false;
    const s = JSON.stringify(snapshot());
    if (s === last) return;
    last = s;
    callDBus(SERVICE, PATH, IFACE, "Snapshot", s);
});
timer.start();
