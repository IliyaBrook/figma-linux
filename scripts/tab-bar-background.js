// Tab bar background on Linux.
//
// Figma's shell page is transparent and relies on the BrowserWindow's
// backgroundColor showing through behind the tab bar. On native Wayland that
// region composites black instead (and see-through during maximize/restore).
// This paints the tab bar with the window's own colour, following Figma's
// light/dark theme changes. It must be loaded AFTER frame-fix-wrapper.js.
//
// This is a workaround for transparent regions rendering black on Wayland;
// remove it once that is fixed upstream in Electron.
(() => {
	if (process.platform !== 'linux') return;

	const electron = require('electron');
	const { app, BrowserWindow, webContents } = electron;

	const cssKeys = new WeakMap();
	let currentBg = null;

	// Electron colours are #RGB, #RRGGBB or #AARRGGBB. Convert to CSS and
	// ignore fully transparent values.
	const toCss = (color) => {
		if (typeof color !== 'string') return null;
		const argb = /^#([0-9a-f]{2})([0-9a-f]{6})$/i.exec(color);
		if (argb) {
			const alpha = argb[1].toLowerCase();
			if (alpha === '00') return null;
			return alpha === 'ff' ? '#' + argb[2] : '#' + argb[2] + alpha;
		}
		return /^#([0-9a-f]{3}|[0-9a-f]{6})$/i.test(color) ? color : null;
	};

	// Only touch the shell page (the one that loads desktop_shell.js), never
	// the figma.com pages inside tabs.
	const apply = async (wc) => {
		try {
			if (!currentBg || wc.isDestroyed()) return;
			const isShell = await wc.executeJavaScript(
				"!!document.querySelector('script[src$=\"desktop_shell.js\"]')"
			);
			if (!isShell) return;
			const key = await wc.insertCSS(
				'[class*="tab_bar--container"]{background-color:' + currentBg + ' !important}'
			);
			const previous = cssKeys.get(wc);
			cssKeys.set(wc, key);
			if (previous) await wc.removeInsertedCSS(previous).catch(() => {});
		} catch (_err) {
			// The page may be navigating or gone; the next dom-ready or colour
			// change tries again.
		}
	};

	const setBackground = (color) => {
		const css = toCss(color);
		if (!css || css === currentBg) return;
		currentBg = css;
		for (const wc of webContents.getAllWebContents()) apply(wc);
	};

	// Figma sets the window colour per theme with setBackgroundColor, so
	// follow it.
	const proto = BrowserWindow.prototype;
	const originalSetBackgroundColor = proto.setBackgroundColor;
	proto.setBackgroundColor = function (color) {
		setBackground(color);
		return originalSetBackgroundColor.apply(this, arguments);
	};

	app.on('web-contents-created', (_event, wc) => {
		wc.on('dom-ready', () => {
			if (!currentBg) {
				for (const win of BrowserWindow.getAllWindows()) {
					if (win.isDestroyed()) continue;
					setBackground(win.getBackgroundColor());
					if (currentBg) break;
				}
			}
			apply(wc);
		});
	});

	console.log('[Frame Fix] Tab bar background fix loaded');
})();
