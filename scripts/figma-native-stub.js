// Stub implementation of Figma native modules (bindings.node + desktop_rust.node) for Linux
// These modules are Windows-specific native addons that need stubbing on Linux

let nativeTheme = null;
try {
	nativeTheme = require('electron').nativeTheme;
} catch (e) {
	// May fail in utility process where electron main APIs aren't available
}

// ---- bindings.node stubs ----
// All methods that xe.* references in main.js

module.exports = {
	// System detection
	isSystemDarkMode: () => nativeTheme ? nativeTheme.shouldUseDarkColors : false,
	isP3ColorSpaceCapable: () => false,
	getCurrentKeyboardLayout: () => 'com.apple.keylayout.US',
	getExecutableVersion: () => '0.0.0',
	getBundleVersion: () => '0',
	getAppPathForProtocol: () => '',
	getActiveNSScreens: () => [],
	getOSNotificationsEnabled: () => true,

	// Window management
	isWindowUnderPoint: () => false,
	getWindowUnderCursor: () => null,
	getWindowScreenshot: () => null,
	forceFocusWindow: () => {},

	// Panel management (macOS-specific NSPanel)
	makePanel: () => null,
	showPanel: () => {},
	hidePanel: () => {},
	positionPanel: () => {},
	destroyPanel: () => {},
	getPanelVisibility: () => false,

	// GPU stats (Windows-specific)
	getWindowsGPUStats: () => ({}),
	getGpuProcessMemorySharedUsageMB: () => 0,
	getGpuProcessMemoryDedicatedUsageMB: () => 0,
	getGpu3dUsageAsync: (callback) => { if (callback) callback(0); },

	// Cursor/Eyedropper (Windows/macOS native)
	startEyedropperSession: () => {},
	stopEyedropperSession: () => {},
	sampleEyedropperAtPoint: () => null,
	setEyedropperCursor: () => {},
	setDefaultCursor: () => {},
	requestEyedropperPermission: () => true,
	updateEyedropperColorSpace: () => {},
	startCursorTracker: () => {},

	// Haptic feedback (macOS-specific)
	triggerHaptic: () => {},

	// File type registration (Windows-specific)
	registerFileTypes: () => {},
	unregisterFileTypes: () => {},

	// Menu shortcuts
	setMenuShortcuts: () => {},

	// Spellcheck / Dictionary
	SetDictionary: () => {},
	GetAvailableDictionaries: () => [],

	// macOS-specific
	launchApp: () => {},
	removeBundleDirectory: () => {},
	removeAgentRegistryLoginItem: () => {},
};

// ---- desktop_rust.node stubs ----
// Used by main.js directly (kl variable) and by bindings_worker.js utility process
// Provides font enumeration on Windows/macOS via native Rust code
module.exports.desktop_rust = {
	// Font enumeration - returns JSON string of font data
	getFonts: () => JSON.stringify({}),
	// Returns timestamp of last font modification
	getFontsModifiedAt: () => 0,
	// Returns JSON string of fonts modified since last check
	getModifiedFonts: () => JSON.stringify({}),
};
