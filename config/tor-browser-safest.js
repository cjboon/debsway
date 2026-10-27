// Tor Browser at the Safest security level, with JavaScript off.
// Used by debsway extras/tor-browser.sh and extras/whonix.sh.
// Tor Browser checks at startup that the prefs bound to the security
// slider match it, and asks for a restart if they don't, so all of them
// are set (from SecurityLevel.sys.mjs in Tor Browser 15). Safest blocks
// JavaScript through NoScript; javascript.enabled turns it off everywhere.
user_pref("browser.security_level.security_slider", 1);
user_pref("browser.security_level.security_custom", false);
user_pref("javascript.options.ion", false);
user_pref("javascript.options.baselinejit", false);
user_pref("javascript.options.native_regexp", false);
user_pref("javascript.options.asmjs", false);
user_pref("javascript.options.wasm", true);
user_pref("mathml.disabled", true);
user_pref("svg.disabled", true);
user_pref("gfx.font_rendering.graphite.enabled", false);
user_pref("gfx.font_rendering.opentype_svg.enabled", false);
user_pref("javascript.enabled", false);
