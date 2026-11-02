// Written by debsway (data/firefox-regular-user.js, installed by
// extras/firefox-regular.sh) into the firefox-regular profile only. Firefox
// reads it at every start, so these come back after a restart; change one for
// good by editing this profile's user.js. Nothing here touches the sandboxed
// Firefox, incognito or the per-site profiles.

// The JavaScript JIT on, for this profile: sites run at full speed.
// (parts/firefox-hardening.sh turns it off for every profile; this undoes it here.)
user_pref("javascript.options.ion", true);
user_pref("javascript.options.baselinejit", true);
user_pref("javascript.options.native_regexp", true);
user_pref("javascript.options.asmjs", true);

// HTTPS-Only Mode: an unencrypted page asks first (one click to go on)
user_pref("dom.security.https_only_mode", true);

// Firefox's standard tracking protection (strict breaks too many sites)
user_pref("browser.contentblocking.category", "standard");

// Nothing sent to Mozilla: no telemetry, health reports or studies
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("app.shield.optoutstudies.enabled", false);
user_pref("app.normandy.enabled", false);
user_pref("browser.discovery.enabled", false);

// No sponsored tiles or stories on the New Tab page, no Pocket
user_pref("browser.newtabpage.activity-stream.showSponsored", false);
user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
user_pref("browser.newtabpage.activity-stream.feeds.section.topstories", false);
// A clean New Tab page, also without the sandboxed Firefox's settings: no
// shortcuts, highlights, weather or search box (and so no Firefox logo), the
// fox wallpaper behind it (shown only with user.enabled, since Firefox 140)
user_pref("browser.newtabpage.activity-stream.feeds.topsites", false);
user_pref("browser.newtabpage.activity-stream.feeds.section.highlights", false);
user_pref("browser.newtabpage.activity-stream.showWeather", false);
user_pref("browser.newtabpage.activity-stream.showSearch", false);
user_pref("browser.newtabpage.activity-stream.newtabWallpapers.enabled", true);
user_pref("browser.newtabpage.activity-stream.newtabWallpapers.user.enabled", true);
user_pref("browser.newtabpage.activity-stream.newtabWallpapers.wallpaper", "dark-fox-anniversary");
user_pref("extensions.pocket.enabled", false);

// Straight to the page: no welcome tour, no "make Firefox your default" nag
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.shell.checkDefaultBrowser", false);
