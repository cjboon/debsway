// Firefox settings for the sandboxed Firefox (debsway extras/firefox-sandbox.sh).
// Applied at every start on top of debsway's defaults for every profile
// (HTTPS-Only Mode, JavaScript JIT off, uBlock Origin in medium mode). Unlike
// incognito, this profile is kept: logins, history and bookmarks stay.

// A clean start page, no first-run pages, no default-browser nag
user_pref("browser.startup.page", 1);
user_pref("browser.startup.homepage", "about:home");
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("datareporting.policy.firstRunURL", "");
user_pref("browser.newtabpage.activity-stream.hideLogo", true);
user_pref("extensions.pocket.enabled", false);

// Tracking, and nothing sent home
user_pref("privacy.trackingprotection.enabled", true);
user_pref("privacy.globalprivacycontrol.enabled", true);
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("browser.ping-centre.telemetry", false);

// Things a page shouldn't be able to ask for. There is no microphone or camera
// in this sandbox anyway; asking is turned off so no site nags.
user_pref("geo.enabled", false);
user_pref("permissions.default.geo", 2);
user_pref("permissions.default.camera", 2);
user_pref("permissions.default.microphone", 2);
user_pref("permissions.default.desktop-notification", 2);
user_pref("dom.push.enabled", false);
user_pref("media.peerconnection.ice.default_address_only", true);

// No guessing ahead
user_pref("network.dns.disablePrefetch", true);
user_pref("network.prefetch-next", false);
user_pref("network.predictor.enabled", false);
user_pref("network.http.speculative-parallel-limit", 0);

// Video is decoded by the CPU: nothing here asks the graphics hardware for help
user_pref("media.hardware-video-decoding.enabled", false);
user_pref("media.ffmpeg.vaapi.enabled", false);
