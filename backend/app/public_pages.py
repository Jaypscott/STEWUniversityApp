from html import escape

from fastapi import APIRouter
from fastapi.responses import HTMLResponse

from app.config.settings import settings


router = APIRouter(tags=["Public legal and support pages"])

SUPPORT_EMAIL = "stewuniversitysupport@gmail.com"
OPERATOR_NAME = "Jaylon"
OPERATOR_LOCATION = "Florida, United States"
EFFECTIVE_DATE = "July 20, 2026"


_STYLES = """
:root {
  color-scheme: light dark;
  --background: #0d0d0f;
  --surface: #17171b;
  --surface-strong: #202026;
  --text: #f7f3e8;
  --muted: #b8b2a5;
  --accent: #e6a817;
  --accent-soft: rgba(230, 168, 23, .14);
  --border: rgba(255, 255, 255, .11);
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
}
* { box-sizing: border-box; }
body {
  margin: 0;
  background:
    radial-gradient(circle at 20% -10%, rgba(230, 168, 23, .18), transparent 34rem),
    var(--background);
  color: var(--text);
  line-height: 1.65;
}
a { color: var(--accent); text-underline-offset: .2em; }
a:hover { text-decoration-thickness: 2px; }
.shell { width: min(100% - 2rem, 760px); margin: 0 auto; }
header { padding: 2rem 0 1rem; }
.brand {
  display: inline-flex;
  align-items: center;
  gap: .65rem;
  color: var(--text);
  font-weight: 760;
  text-decoration: none;
  letter-spacing: -.02em;
}
.brand-mark {
  display: grid;
  width: 2.25rem;
  height: 2.25rem;
  place-items: center;
  border-radius: .75rem;
  background: var(--accent);
  color: #15100a;
  font-size: .8rem;
}
nav { display: flex; flex-wrap: wrap; gap: .75rem 1rem; margin-top: 1.25rem; }
nav a { color: var(--muted); font-size: .9rem; text-decoration: none; }
nav a[aria-current="page"] { color: var(--accent); }
main { padding: 2.5rem 0 5rem; }
.eyebrow {
  margin: 0 0 .75rem;
  color: var(--accent);
  font-size: .78rem;
  font-weight: 750;
  letter-spacing: .12em;
  text-transform: uppercase;
}
h1 { margin: 0; font-size: clamp(2.25rem, 9vw, 4.6rem); line-height: .98; letter-spacing: -.055em; }
.lede { margin: 1.25rem 0 0; color: var(--muted); font-size: 1.08rem; }
.meta { margin: 1rem 0 0; color: var(--muted); font-size: .88rem; }
.card {
  margin-top: 2rem;
  padding: clamp(1.15rem, 4vw, 2rem);
  border: 1px solid var(--border);
  border-radius: 1.25rem;
  background: linear-gradient(145deg, var(--surface-strong), var(--surface));
  box-shadow: 0 1.5rem 4rem rgba(0, 0, 0, .18);
}
h2 { margin: 2.25rem 0 .55rem; font-size: 1.35rem; line-height: 1.25; letter-spacing: -.02em; }
.card h2:first-child { margin-top: 0; }
h3 { margin: 1.5rem 0 .4rem; font-size: 1rem; }
p { margin: .65rem 0; }
ul, ol { padding-left: 1.35rem; }
li + li { margin-top: .45rem; }
.callout {
  margin: 1.25rem 0;
  padding: 1rem 1.1rem;
  border-left: .25rem solid var(--accent);
  border-radius: 0 .8rem .8rem 0;
  background: var(--accent-soft);
}
.button {
  display: inline-flex;
  margin-top: 1rem;
  padding: .78rem 1rem;
  border-radius: .8rem;
  background: var(--accent);
  color: #15100a;
  font-weight: 750;
  text-decoration: none;
}
footer { padding: 1.5rem 0 3rem; border-top: 1px solid var(--border); color: var(--muted); font-size: .85rem; }
@media (prefers-color-scheme: light) {
  :root {
    --background: #fbf8f0;
    --surface: #ffffff;
    --surface-strong: #fffdf8;
    --text: #1d1b17;
    --muted: #686257;
    --border: rgba(24, 20, 12, .12);
  }
  body { background: radial-gradient(circle at 20% -10%, rgba(230, 168, 23, .2), transparent 34rem), var(--background); }
}
"""


def _page(
    *,
    path: str,
    title: str,
    eyebrow: str,
    description: str,
    body: str,
) -> HTMLResponse:
    navigation = (
        ("/legal/terms", "Terms"),
        ("/legal/privacy", "Privacy"),
        ("/support", "Support"),
        ("/safety", "Safety"),
    )
    nav_items: list[str] = []
    for href, label in navigation:
        current = ' aria-current="page"' if href == path else ""
        nav_items.append(f'<a href="{href}"{current}>{label}</a>')
    nav = "".join(nav_items)
    canonical = f"{settings.public_base_url}{path}"
    document = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="description" content="{escape(description)}">
  <link rel="canonical" href="{escape(canonical, quote=True)}">
  <title>{escape(title)} · STEW University</title>
  <style>{_STYLES}</style>
</head>
<body>
  <header class="shell">
    <a class="brand" href="/"><span class="brand-mark">STEW</span><span>STEW University</span></a>
    <nav aria-label="Legal and support">{nav}</nav>
  </header>
  <main class="shell">
    <p class="eyebrow">{escape(eyebrow)}</p>
    <h1>{escape(title)}</h1>
    <p class="lede">{escape(description)}</p>
    <p class="meta">Effective {EFFECTIVE_DATE}</p>
    <article class="card">{body}</article>
  </main>
  <footer><div class="shell">Operated by {OPERATOR_NAME} in {OPERATOR_LOCATION}. Contact <a href="mailto:{SUPPORT_EMAIL}">{SUPPORT_EMAIL}</a>.</div></footer>
</body>
</html>"""
    return HTMLResponse(
        document,
        headers={
            "Cache-Control": "public, max-age=300",
            "Content-Security-Policy": (
                "default-src 'none'; style-src 'unsafe-inline'; img-src data:; "
                "base-uri 'none'; frame-ancestors 'none'"
            ),
            "Referrer-Policy": "no-referrer",
            "X-Content-Type-Options": "nosniff",
        },
    )


@router.get("/legal/terms", response_class=HTMLResponse)
async def terms_page() -> HTMLResponse:
    return _page(
        path="/legal/terms",
        title="Terms of Use",
        eyebrow="Agreement",
        description="The rules for using STEW University and its Band collaboration service.",
        body=f"""
<h2>1. Agreement and operator</h2>
<p>These Terms of Use (the “Terms”) are an agreement between you and STEW University, operated by {OPERATOR_NAME} in {OPERATOR_LOCATION} (“STEW,” “we,” “us,” or “our”). By accessing STEW University or creating a Band profile, you agree to these Terms and our <a href="/legal/privacy">Privacy Policy</a>.</p>

<h2>2. Who may use Band</h2>
<p>Band is intended for people age 13 and older. You may not use Band if you are under 13. If you are under the age of legal majority where you live, you represent that a parent or legal guardian has reviewed and agreed to these Terms where their consent is required.</p>

<h2>3. Accounts and security</h2>
<p>Band uses Sign in with Apple. You are responsible for your Apple account, devices, and activity under your STEW profile. Provide accurate profile information, protect access to your device, and notify us at <a href="mailto:{SUPPORT_EMAIL}">{SUPPORT_EMAIL}</a> if you believe your account has been compromised.</p>

<h2>4. Acceptable use</h2>
<p>You agree not to:</p>
<ul>
  <li>harass, threaten, exploit, impersonate, or harm another person;</li>
  <li>post hateful, sexually exploitative, unlawfully violent, fraudulent, or otherwise illegal content;</li>
  <li>upload content you do not have the right to use, including copyrighted recordings or images;</li>
  <li>send spam, distribute malware, probe the service, evade limits, or interfere with other users;</li>
  <li>collect another person’s information without authorization; or</li>
  <li>use the service to violate law or another person’s rights.</li>
</ul>
<p>Review the <a href="/safety">Safety Center</a> for reporting and blocking information.</p>

<h2>5. Your content</h2>
<p>You retain ownership of music, recordings, images, text, and other material you submit (“User Content”). You grant STEW a non-exclusive, worldwide, royalty-free license to host, copy, process, transmit, display, and modify User Content only as reasonably necessary to operate, secure, moderate, and improve the service. This license ends when the content is deleted, subject to reasonable technical delays, backups, and legal obligations.</p>
<p>You are responsible for your User Content and represent that you have the rights needed to submit it. Band members with access to a shared Band may view, download, discuss, and collaborate on content according to their permissions.</p>

<h2>6. Moderation</h2>
<p>We may investigate reports, remove content, restrict features, suspend accounts, or preserve information when reasonably necessary to enforce these Terms, protect users, or comply with law. We do not promise to monitor every submission and do not endorse User Content.</p>

<h2>7. AI features</h2>
<p>STEW includes AI-assisted music education and songwriting features. AI output can be incomplete, inaccurate, or unsuitable. Review it before relying on or publishing it. Do not submit confidential information or content you lack permission to share. AI output is provided for creative and educational assistance, not professional, legal, medical, or financial advice.</p>

<h2>8. Service changes and availability</h2>
<p>We may add, change, suspend, or discontinue features. We work to keep STEW available, but do not guarantee uninterrupted or error-free operation. You are responsible for keeping independent copies of important recordings and other material.</p>

<h2>9. Ending use and account deletion</h2>
<p>You may stop using STEW at any time. Band settings include an account-deletion flow. Band owners must transfer or delete Bands they own before deleting their account. Deletion revokes access and removes associated profile data, authored collaboration content, and uploaded media through a background process; a non-identifying record may remain where needed to preserve shared project integrity. We may retain limited information when required for security, fraud prevention, dispute resolution, or law.</p>

<h2>10. Intellectual property</h2>
<p>Other than User Content, STEW’s software, design, branding, and service materials are owned by STEW or its licensors. These Terms provide a limited, personal, non-transferable, revocable right to use the service; they do not transfer ownership of STEW intellectual property.</p>

<h2>11. Disclaimers</h2>
<p>To the maximum extent permitted by law, the service is provided “as is” and “as available,” without warranties of merchantability, fitness for a particular purpose, non-infringement, or uninterrupted availability. Nothing in these Terms limits rights or warranties that cannot lawfully be excluded.</p>

<h2>12. Limitation of liability</h2>
<p>To the maximum extent permitted by law, STEW and its operator will not be liable for indirect, incidental, special, consequential, exemplary, or punitive damages, or for lost data, profits, opportunities, or goodwill arising from the service. STEW’s total liability for a claim will not exceed the greater of US $100 or the amount you paid STEW during the 12 months before the event giving rise to the claim. These limits do not apply where prohibited by law.</p>

<h2>13. Governing law</h2>
<p>These Terms are governed by the laws of Florida and applicable United States federal law, without regard to conflict-of-law principles. Courts with jurisdiction in Florida will have jurisdiction over disputes, except where consumer law gives you the right to proceed elsewhere.</p>

<h2>14. Changes and contact</h2>
<p>We may update these Terms as the service changes. We will revise the effective date and provide additional notice when required. Continued use after an update takes effect constitutes acceptance of the updated Terms.</p>
<p>Questions may be sent to <a href="mailto:{SUPPORT_EMAIL}">{SUPPORT_EMAIL}</a>.</p>
""",
    )


@router.get("/legal/privacy", response_class=HTMLResponse)
async def privacy_page() -> HTMLResponse:
    return _page(
        path="/legal/privacy",
        title="Privacy Policy",
        eyebrow="Your information",
        description="How STEW University collects, uses, shares, retains, and deletes information.",
        body=f"""
<h2>1. Scope and contact</h2>
<p>This Privacy Policy applies to STEW University’s iOS app and supporting services, including Band. STEW University is operated by {OPERATOR_NAME} in {OPERATOR_LOCATION}. Questions and privacy requests can be sent to <a href="mailto:{SUPPORT_EMAIL}">{SUPPORT_EMAIL}</a>.</p>

<h2>2. Information we collect</h2>
<h3>Account and profile information</h3>
<ul>
  <li><strong>Sign in with Apple:</strong> Apple’s account identifier, and your name or email address when Apple makes them available. An email may be an Apple private-relay address.</li>
  <li><strong>Band profile:</strong> username, display name, profile status, Terms acceptance, account role, and account timestamps.</li>
  <li><strong>Age eligibility:</strong> you provide a birth year to confirm that you are at least 13. The Band user record stores that the age check was completed, rather than storing the birth year.</li>
</ul>

<h3>Content and collaboration information</h3>
<p>We process Bands, memberships, invitations, projects, tracks, takes, mood-board posts, links, comments, reactions, mentions, reports, block lists, notification history, and related metadata. Uploaded content may include audio, video, images, filenames, file types, sizes, duration, and technical validation data.</p>

<h3>Device, security, and support information</h3>
<p>We process session tokens, Apple authorization data, push-notification device tokens and environment, notification delivery results, IP-address-derived rate-limit identifiers, app installation identifiers used for AI limits, security records, and information you include in support or safety communications. Rate-limit identifiers are hashed before storage.</p>

<h3>AI requests</h3>
<p>When you use AI features, your prompt and up to eight recent conversation messages are sent to OpenAI to generate a response. STEW does not add those requests to the Band collaboration database. Your device may keep recent songwriting messages locally so the conversation can be restored.</p>

<h2>3. How we use information</h2>
<ul>
  <li>authenticate users, maintain sessions, and provide account recovery and deletion;</li>
  <li>provide private Band collaboration, media storage, invitations, and notifications;</li>
  <li>generate AI-assisted music education and songwriting responses;</li>
  <li>enforce usage limits and protect against abuse, fraud, and security threats;</li>
  <li>review reports, block abusive users, moderate content, and enforce our Terms;</li>
  <li>respond to support, privacy, copyright, and safety requests; and</li>
  <li>comply with legal obligations and protect users’ and STEW’s rights.</li>
</ul>

<h2>4. How information is disclosed</h2>
<ul>
  <li><strong>Other Band members:</strong> profile details and User Content are visible to members of Bands where you participate, according to their roles and access.</li>
  <li><strong>Service providers:</strong> Render provides application, database, and job infrastructure; Cloudflare R2 stores private media; Apple provides sign-in and push notifications; and OpenAI processes AI prompts and responses. They process information to provide services to STEW under their applicable terms and safeguards.</li>
  <li><strong>Legal and safety:</strong> we may disclose information when reasonably necessary to comply with law, respond to valid legal process, investigate abuse, or protect a person’s safety or rights.</li>
  <li><strong>Business changes:</strong> information may be transferred as part of a merger, financing, reorganization, or sale, subject to applicable law and continued protection.</li>
</ul>
<div class="callout"><strong>No sale or targeted advertising.</strong> The current version of STEW does not sell personal information or use third-party advertising SDKs for targeted advertising.</div>

<h2>5. Storage and security</h2>
<p>Band account and collaboration records are stored in managed infrastructure, while private media is stored in Cloudflare R2 and accessed using time-limited signed URLs. We use encryption in transit, access controls, hashed refresh tokens, encrypted Apple credentials, scoped storage credentials, and other administrative and technical safeguards. No service can guarantee absolute security.</p>

<h2>6. Retention and deletion</h2>
<p>We retain account and collaboration information while needed to provide Band, maintain shared projects, meet security needs, and comply with law. Upload reservations expire automatically, and abandoned uploads are removed. Rate-limit entries expire with their configured usage windows.</p>
<p>You can initiate deletion in <strong>Band → Settings → Delete account</strong>. Owners must first transfer or delete Bands they own. Access is revoked immediately and a background process removes your Apple identity, sessions, device registrations, authored posts and comments, uploaded media, memberships, reports, invitations, and block relationships. A non-identifying user record may remain where required to preserve shared project relationships. Limited records may also remain in backups or where retention is legally required.</p>
<p>You can also contact <a href="mailto:{SUPPORT_EMAIL}">{SUPPORT_EMAIL}</a> with privacy questions. Support contact is not a substitute for the in-app account-deletion control.</p>

<h2>7. Your choices</h2>
<ul>
  <li>Decline push notifications or disable them in iOS Settings.</li>
  <li>Leave a Band, block another user, or report a user or piece of content.</li>
  <li>Remove your posts or media where the app provides deletion controls.</li>
  <li>Delete your Band account through the in-app settings.</li>
  <li>Contact us to request access, correction, or other privacy rights available where you live.</li>
</ul>

<h2>8. Children</h2>
<p>Band is a general-audience collaboration feature for people age 13 and older. We do not knowingly allow children under 13 to create Band profiles. If you believe a child under 13 has provided personal information, contact us so we can investigate and delete it as appropriate.</p>

<h2>9. International processing</h2>
<p>STEW is operated from the United States. Information may be processed in the United States and other locations where service providers operate, subject to applicable legal protections.</p>

<h2>10. Changes</h2>
<p>We may update this policy as STEW changes. We will update the effective date and provide additional notice when required. Material changes apply prospectively unless law permits otherwise.</p>
""",
    )


@router.get("/support", response_class=HTMLResponse)
async def support_page() -> HTMLResponse:
    return _page(
        path="/support",
        title="Support",
        eyebrow="We can help",
        description="Troubleshooting and account help for STEW University.",
        body=f"""
<h2>Contact support</h2>
<p>Email <a href="mailto:{SUPPORT_EMAIL}">{SUPPORT_EMAIL}</a> with a description of the problem, the app version, your iOS version, and what you expected to happen.</p>
<a class="button" href="mailto:{SUPPORT_EMAIL}?subject=STEW%20University%20Support">Email STEW Support</a>
<div class="callout"><strong>Protect your account.</strong> Never email passwords, Apple authorization codes, session tokens, private keys, or Render and Cloudflare credentials. STEW support will not ask for them.</div>

<h2>Sign in with Apple</h2>
<ol>
  <li>Confirm the device has an internet connection and is signed in to iCloud.</li>
  <li>Close and reopen STEW University, then try <strong>Continue with Apple</strong> once.</li>
  <li>If the problem continues, include the exact error message and approximate time in your support email.</li>
</ol>

<h2>Media uploads</h2>
<p>Keep STEW open until an upload finishes. Images may be up to 20 MB; audio and video may be up to 100 MB, and each Band has a 2 GB media limit. If an upload expires or fails validation, start a new upload.</p>

<h2>Notifications</h2>
<p>Enable notifications in iOS Settings for STEW University. Notification delivery can also depend on network conditions, Focus settings, and Band activity.</p>

<h2>Account deletion</h2>
<p>Open <strong>Band → Settings → Delete account</strong>. If you own a Band, transfer ownership or delete that Band first. You will confirm the request with Apple, access will be revoked, and associated content and media will be removed by the deletion process.</p>

<h2>Safety, abuse, and copyright</h2>
<p>Use the in-app Report and Block actions whenever possible. For urgent safety concerns, harassment, copyright notices, or content you cannot report in the app, review the <a href="/safety">Safety Center</a> and email us.</p>
""",
    )


@router.get("/safety", response_class=HTMLResponse)
async def safety_page() -> HTMLResponse:
    return _page(
        path="/safety",
        title="Safety Center",
        eyebrow="Community care",
        description="How to report abuse, block users, and contact STEW about urgent concerns.",
        body=f"""
<div class="callout"><strong>Immediate danger:</strong> STEW is not an emergency service. If someone may be in immediate danger, contact local emergency services or an appropriate crisis resource in your location.</div>

<h2>Report content or a user</h2>
<p>In Band, open the relevant card, post, or member menu and choose <strong>Report</strong>. Select the reason and add concise context. Reports are restricted to the platform safety review process.</p>
<p>For an issue you cannot report in the app, email <a href="mailto:{SUPPORT_EMAIL}?subject=STEW%20Safety%20Report">{SUPPORT_EMAIL}</a>. Include the Band name, username, content type, approximate date, and a factual description. Do not forward illegal material; identify where it appears instead.</p>

<h2>Block a user</h2>
<p>Open the member’s actions and choose <strong>Block user</strong>. You can review blocked users under Band settings. Blocking is a personal safety control; also submit a report when conduct may violate the Terms or threaten others.</p>

<h2>What we review</h2>
<p>Reports may cover harassment, hate, threats or violence, explicit or exploitative material, spam, copyright concerns, impersonation, and other violations of the <a href="/legal/terms">Terms of Use</a>. STEW may remove content, restrict access, suspend an account, preserve relevant records, or contact authorities when reasonably necessary and lawful.</p>

<h2>Copyright notices</h2>
<p>Send copyright concerns to <a href="mailto:{SUPPORT_EMAIL}?subject=Copyright%20Notice">{SUPPORT_EMAIL}</a>. Include your contact information, the work you believe is infringed, the location of the reported material, a good-faith statement that the use is unauthorized, a statement that your notice is accurate and that you are authorized to act, and your physical or electronic signature. Misrepresentations may have legal consequences.</p>

<h2>Privacy and retaliation</h2>
<p>Safety reports are used to investigate and resolve concerns. Information may be shared when needed to investigate, protect users, or comply with law. Retaliation against a person for making a good-faith report is prohibited.</p>
""",
    )
