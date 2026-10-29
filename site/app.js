(function () {
  const cfg = window.ROOM_RIG_SITE || {};
  const statusEl = () => document.getElementById("status");

  function setStatus(msg) {
    const el = statusEl();
    if (el) el.textContent = msg || "";
  }

  function client() {
    if (!cfg.supabaseUrl || !cfg.supabaseAnonKey) {
      throw new Error(
        "Supabase is not configured for this site build (missing URL/anon key)."
      );
    }
    if (!window.supabase) {
      throw new Error("Supabase JS failed to load.");
    }
    return window.supabase.createClient(cfg.supabaseUrl, cfg.supabaseAnonKey, {
      auth: {
        persistSession: true,
        detectSessionInUrl: true,
        flowType: "pkce",
      },
    });
  }

  async function currentSession() {
    const sb = client();
    const { data } = await sb.auth.getSession();
    return data.session;
  }

  async function loadProfile(userId) {
    const sb = client();
    const { data, error } = await sb
      .from("profiles")
      .select("id, display_name, avatar_url, is_admin")
      .eq("id", userId)
      .maybeSingle();
    if (error) throw error;
    return data;
  }

  /** Admin gate: profiles.is_admin only (writable by service_role / SQL, not clients). */
  function isAdminUser(_session, profile) {
    return profile?.is_admin === true;
  }

  async function refreshAuthChrome() {
    const slot = document.getElementById("auth-slot");
    if (!slot) return;
    try {
      const session = await currentSession();
      if (!session) {
        slot.innerHTML =
          '<a class="btn" href="/auth">Sign in</a>';
        return;
      }
      const name =
        (await loadProfile(session.user.id))?.display_name ||
        session.user.email ||
        "Signed in";
      slot.innerHTML =
        `<span class="muted">${escapeHtml(name)}</span> ` +
        `<button type="button" class="btn" id="sign-out-btn">Sign out</button>`;
      document.getElementById("sign-out-btn")?.addEventListener("click", async () => {
        await client().auth.signOut();
        location.reload();
      });
    } catch (e) {
      slot.innerHTML = '<a class="btn" href="/auth">Sign in</a>';
      console.warn(e);
    }
  }

  function escapeHtml(s) {
    return String(s)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;");
  }

  async function initAuthPage() {
    const form = document.getElementById("auth-form");
    if (!form) return;
    const modeToggle = document.getElementById("mode-toggle");
    let signUp = new URLSearchParams(location.search).get("mode") === "signup";

    function paintMode() {
      const title = document.getElementById("auth-title");
      const submit = document.getElementById("auth-submit");
      if (title) title.textContent = signUp ? "Sign up" : "Sign in";
      if (submit) submit.textContent = signUp ? "Create account" : "Sign in";
      if (modeToggle) {
        modeToggle.textContent = signUp
          ? "Already have an account? Sign in"
          : "Need an account? Sign up";
      }
    }
    paintMode();
    modeToggle?.addEventListener("click", (e) => {
      e.preventDefault();
      signUp = !signUp;
      paintMode();
    });

    document.getElementById("google-btn")?.addEventListener("click", async () => {
      try {
        setStatus("Redirecting to Google…");
        const sb = client();
        const { error } = await sb.auth.signInWithOAuth({
          provider: "google",
          options: {
            redirectTo: `${location.origin}/auth`,
          },
        });
        if (error) setStatus(error.message);
      } catch (e) {
        setStatus(e.message || String(e));
      }
    });

    form.addEventListener("submit", async (e) => {
      e.preventDefault();
      const email = document.getElementById("email")?.value?.trim();
      const password = document.getElementById("password")?.value || "";
      if (!email || !password) {
        setStatus("Email and password are required.");
        return;
      }
      try {
        const sb = client();
        setStatus(signUp ? "Creating account…" : "Signing in…");
        if (signUp) {
          const { error } = await sb.auth.signUp({
            email,
            password,
            options: { emailRedirectTo: `${location.origin}/auth` },
          });
          if (error) throw error;
          setStatus("Check your email to confirm, or sign in if confirm is off.");
        } else {
          const { error } = await sb.auth.signInWithPassword({ email, password });
          if (error) throw error;
          location.href = "/";
        }
      } catch (err) {
        setStatus(err.message || String(err));
      }
    });

    try {
      const session = await currentSession();
      if (session) setStatus(`Signed in as ${session.user.email || session.user.id}`);
    } catch (e) {
      setStatus(e.message || String(e));
    }
  }

  async function initDownloadPage() {
    const btn = document.getElementById("download-btn");
    const note = document.getElementById("download-note");
    const url = cfg.githubReleasesUrl || "https://github.com/yksu0/Room_Rig/releases";
    if (btn) {
      btn.href = url;
      btn.addEventListener("click", (e) => {
        // Always open Releases; copy states APK may not exist yet.
      });
    }
    if (note) {
      note.textContent =
        "Android APK ships via GitHub Releases. No build is uploaded yet — " +
        "the button opens the Releases page (empty until a named tag like v1.0.0+1).";
    }
  }

  async function initAdminPage() {
    const gate = document.getElementById("admin-gate");
    const body = document.getElementById("admin-body");
    if (!gate || !body) return;
    try {
      const session = await currentSession();
      if (!session) {
        gate.innerHTML =
          '<p>Sign in required.</p><p><a class="btn btn-primary" href="/auth">Sign in</a></p>';
        return;
      }
      const profile = await loadProfile(session.user.id);
      if (!isAdminUser(session, profile)) {
        gate.innerHTML =
          "<p>This account is not flagged as admin.</p>" +
          "<p class='muted'>Flip with SQL (service_role / dashboard only — clients cannot set this): " +
          "<code>UPDATE profiles SET is_admin = true WHERE id = '…';</code></p>";
        body.hidden = true;
        return;
      }
      gate.innerHTML =
        "<p>Admin access granted. Full CRUD for baselines / featured / hide lands next.</p>";
      body.hidden = false;
    } catch (e) {
      gate.textContent = e.message || String(e);
    }
  }

  document.addEventListener("DOMContentLoaded", async () => {
    await refreshAuthChrome();
    await initAuthPage();
    await initDownloadPage();
    await initAdminPage();
  });
})();
