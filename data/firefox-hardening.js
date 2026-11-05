// Written by Wren Linux (data/firefox-hardening.js, installed by
// parts/firefox-hardening.sh). Defaults for every
// profile; a profile can change them at about:config.

// HTTPS-Only Mode: no unencrypted pages without asking first
pref("dom.security.https_only_mode", true);

// No "save this password?" and no made-up passwords: KeePassXC keeps them,
// encrypted with your own passphrase, apart from the browser pages run in (the
// policy OfferToSaveLogins locks the first; logins saved before stay listed)
pref("signon.rememberSignons", false);
pref("signon.generation.enabled", false);
pref("signon.firefoxRelay.feature", "disabled");

// JavaScript JIT off: slower JavaScript, much less to attack
pref("javascript.options.ion", false);
pref("javascript.options.baselinejit", false);
pref("javascript.options.native_regexp", false);
pref("javascript.options.asmjs", false);

// Open straight to the home page: no Mozilla welcome, first-run or
// whats-new tabs, and no "make Firefox your default browser" nag.
pref("browser.aboutwelcome.enabled", false);
pref("browser.startup.homepage_override.mstone", "ignore");
pref("browser.shell.checkDefaultBrowser", false);
pref("datareporting.policy.firstRunURL", "");

// A blank Firefox Home / New Tab: no shortcuts, sponsored tiles,
// stories, highlights, weather or the centre search box (the address
// bar searches, with DuckDuckGo as the default from policies.json).
pref("browser.newtabpage.activity-stream.feeds.topsites", false);
pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
pref("browser.newtabpage.activity-stream.feeds.section.topstories", false);
pref("browser.newtabpage.activity-stream.showSponsored", false);
pref("browser.newtabpage.activity-stream.feeds.section.highlights", false);
pref("browser.newtabpage.activity-stream.showWeather", false);
pref("browser.newtabpage.activity-stream.showSearch", false);

// ...with the fox wallpaper you use (Firefox 128+ New Tab wallpapers).
pref("browser.newtabpage.activity-stream.newtabWallpapers.enabled", true);
pref("browser.newtabpage.activity-stream.newtabWallpapers.v2.enabled", true);
pref("browser.newtabpage.activity-stream.newtabWallpapers.wallpaper", "dark-fox-anniversary");
// Firefox 140+ shows the chosen wallpaper only with this on (it is off until
// you pick one in the page's own settings)
pref("browser.newtabpage.activity-stream.newtabWallpapers.user.enabled", true);
