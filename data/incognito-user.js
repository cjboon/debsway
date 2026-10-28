// Firefox settings for the incognito user (debsway parts/incognito.sh).
// The profile is thrown away when the browser closes. These also stop it
// from writing anything while it runs, and turn off what can leak. They
// come on top of debsway's defaults for every profile (HTTPS-Only Mode,
// JavaScript JIT off, uBlock Origin in medium mode).

// Always private browsing; nothing kept on disk
user_pref("browser.privatebrowsing.autostart", true);
user_pref("browser.cache.disk.enable", false);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("places.history.enabled", false);
user_pref("browser.formfill.enable", false);
user_pref("signon.rememberSignons", false);
user_pref("network.cookie.lifetimePolicy", 2);

// Tracking and fingerprinting. resistFingerprinting makes the browser look
// the same for everyone (UTC time, rounded timers, fixed window sizes) and
// breaks a few sites: set it to false here to turn it off.
user_pref("privacy.trackingprotection.enabled", true);
user_pref("privacy.globalprivacycontrol.enabled", true);
user_pref("privacy.resistFingerprinting", true);

// Video and sound work (YouTube and the like): the CPU decodes, since there
// is no graphics card to ask, and the sound goes to incognito's own audio
// server. Nothing here asks the hardware for help.
user_pref("media.hardware-video-decoding.enabled", false);
user_pref("media.ffmpeg.vaapi.enabled", false);

// Things a page shouldn't be able to ask for
user_pref("geo.enabled", false);
user_pref("permissions.default.geo", 2);
user_pref("permissions.default.camera", 2);
user_pref("permissions.default.microphone", 2);
user_pref("permissions.default.desktop-notification", 2);
user_pref("dom.push.enabled", false);
user_pref("webgl.disabled", true);
user_pref("media.eme.enabled", false);
user_pref("media.peerconnection.ice.default_address_only", true);

// No guessing ahead, no reports
user_pref("network.dns.disablePrefetch", true);
user_pref("network.prefetch-next", false);
user_pref("network.predictor.enabled", false);
user_pref("network.http.speculative-parallel-limit", 0);
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("browser.ping-centre.telemetry", false);

// The first window opens on Firefox's own home page (the same one as a new
// tab), without the Firefox logo in the middle of it, and no first-run pages
user_pref("browser.startup.page", 1);
user_pref("browser.startup.homepage", "about:home");
user_pref("browser.newtabpage.activity-stream.hideLogo", true);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("datareporting.policy.firstRunURL", "");
user_pref("extensions.pocket.enabled", false);
