# InfraCortex HUD (Windows). Custom-drawn, DPI-aware, always-on-top panel showing every devops agent that is
# working right now: who (agent), where (app + project), what (task + last steps), how long, and the result.
# Started by agent_events.py; reads <StateDir>\state.json, writes <StateDir>\heartbeat; exits after 90 s idle.
# ASCII-only source (Windows PowerShell 5.1); the C# below is C# 5 (no interpolated strings, no ?., no =>-members).
param([Parameter(Mandatory = $true)][string]$StateDir)

Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing, System.Web.Extensions -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;

public class HudStep { public string Text; public bool Ok; }

public class HudAgent {
    public string Id, Type, Status, Result, Action, Task, Source, Project, Summary;
    public double Started, Ended, Seen; public int Steps, Errors; public bool Mcp;
    public List<HudStep> History = new List<HudStep>();
}

public class DevOpsHud : Form {
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] static extern bool ReleaseCapture();
    [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h, int m, int w, int l);

    static readonly string DOT = "  " + (char)0xB7 + "  ";
    static readonly Dictionary<string, string[]> Meta = new Dictionary<string, string[]> {
        { "terraform-engineer", new[] { "Terraform Engineer", "TF", "#8B5CF6" } },
        { "k8s-troubleshooter", new[] { "Kubernetes Troubleshooter", "K8s", "#3B82F6" } },
        { "docker-engineer",    new[] { "Docker Engineer", "DK", "#06B6D4" } },
        { "finops-analyst",     new[] { "FinOps Analyst", "FO", "#22C55E" } },
        { "cortex",             new[] { "Cortex", "CX", "#F97316" } } };

    readonly string stateDir;
    List<HudAgent> agents = new List<HudAgent>();
    float S = 1f; int angle; int shimmer; bool collapsed, moved; DateTime idleSince = DateTime.UtcNow;
    Rectangle closeBtn, collapseBtn;
    readonly Font fTitle, fName, fSmall, fMono, fPill, fAvatar;
    readonly System.Windows.Forms.Timer anim = new System.Windows.Forms.Timer(), data = new System.Windows.Forms.Timer();

    const int W = 384, HEAD = 44, CARD = 134, GAP = 8, PAD = 10, MAXCARDS = 4;

    static Color C(string hex) { return ColorTranslator.FromHtml(hex); }
    int P(float v) { return (int)Math.Round(v * S); }
    static double Now() { return (DateTime.UtcNow - new DateTime(1970, 1, 1)).TotalSeconds; }

    public DevOpsHud(string dir) {
        stateDir = dir;
        FormBorderStyle = FormBorderStyle.None; TopMost = true; ShowInTaskbar = false; StartPosition = FormStartPosition.Manual;
        BackColor = C("#14161B"); DoubleBuffered = true;
        SetStyle(ControlStyles.ResizeRedraw | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer, true);
        using (Graphics g = CreateGraphics()) { S = g.DpiX / 96f; }
        fTitle = new Font("Segoe UI Semibold", 10f); fName = new Font("Segoe UI Semibold", 10f); fSmall = new Font("Segoe UI", 8.25f);
        fMono = new Font("Cascadia Mono", 8f); if (fMono.Name != "Cascadia Mono") fMono = new Font("Consolas", 8.25f);
        fPill = new Font("Segoe UI Semibold", 7.5f); fAvatar = new Font("Segoe UI", 9.5f, FontStyle.Bold);
        Width = P(W); Height = P(HEAD);
        anim.Interval = 50;
        anim.Tick += delegate { angle = (angle + 9) % 360; shimmer = (shimmer + 4) % 200; if (agents.Any(a => a.Status == "running")) Invalidate(); };
        data.Interval = 500; data.Tick += delegate { Reload(); };
        MouseDown += OnMouseDownHud;
        Load += delegate { Reload(); anim.Start(); data.Start(); };
    }

    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams {
        get { CreateParams p = base.CreateParams; p.ExStyle |= 0x08000000 | 0x00000080 | 0x00000008; return p; }   // NOACTIVATE|TOOLWINDOW|TOPMOST
    }

    void OnMouseDownHud(object sender, MouseEventArgs e) {
        if (closeBtn.Contains(e.Location)) { Close(); return; }
        if (collapseBtn.Contains(e.Location)) { collapsed = !collapsed; Relayout(); Invalidate(); return; }
        ReleaseCapture(); SendMessage(Handle, 0xA1, 0x2, 0); moved = true;
    }

    static double D(Dictionary<string, object> d, string k) { object v; return d.TryGetValue(k, out v) && v != null ? Convert.ToDouble(v) : 0; }
    static string Str(Dictionary<string, object> d, string k) { object v; return d.TryGetValue(k, out v) && v != null ? Convert.ToString(v) : ""; }

    void Reload() {
        try { File.WriteAllText(Path.Combine(stateDir, "heartbeat"), ((long)Now()).ToString()); } catch { }
        List<HudAgent> list = new List<HudAgent>();
        try {
            string raw;
            using (FileStream fs = new FileStream(Path.Combine(stateDir, "state.json"), FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            using (StreamReader sr = new StreamReader(fs)) { raw = sr.ReadToEnd(); }
            Dictionary<string, object> root = new JavaScriptSerializer().DeserializeObject(raw) as Dictionary<string, object>;
            object ao; Dictionary<string, object> all = root != null && root.TryGetValue("agents", out ao) ? ao as Dictionary<string, object> : null;
            double now = Now();
            if (all != null) foreach (KeyValuePair<string, object> kv in all) {
                if (kv.Key.StartsWith("pending:")) continue;
                Dictionary<string, object> a = kv.Value as Dictionary<string, object>; if (a == null) continue;
                HudAgent h = new HudAgent { Id = kv.Key, Type = Str(a, "type"), Status = Str(a, "status"), Result = Str(a, "result"),
                    Action = Str(a, "action"), Task = Str(a, "task"), Source = Str(a, "source"), Project = Str(a, "project"), Summary = Str(a, "summary"),
                    Started = D(a, "started"), Ended = D(a, "ended"), Seen = D(a, "seen"), Steps = (int)D(a, "steps"), Errors = (int)D(a, "errors"),
                    Mcp = kv.Key.StartsWith("mcp:") };
                if (h.Seen == 0) h.Seen = h.Started;
                if (h.Ended > 0 && now - h.Ended > (h.Mcp ? 20 : 15)) continue;      // finished cards linger briefly
                object ho; object[] hist = a.TryGetValue("history", out ho) ? ho as object[] : null;
                if (hist != null) foreach (object o in hist) {
                    Dictionary<string, object> st = o as Dictionary<string, object>;
                    if (st != null) h.History.Add(new HudStep { Text = Str(st, "a"), Ok = !(st.ContainsKey("ok") && st["ok"] is bool && !(bool)st["ok"]) });
                }
                list.Add(h);
            }
        } catch { return; }
        agents = list.OrderBy(a => a.Status == "running" ? 0 : 1).ThenBy(a => a.Started).ToList();
        if (agents.Count == 0) { if (Visible) Hide(); if ((DateTime.UtcNow - idleSince).TotalSeconds > 90) Close(); return; }
        idleSince = DateTime.UtcNow;
        Relayout(); if (!Visible) Show(); Invalidate();
    }

    void Relayout() {
        int n = collapsed ? 0 : Math.Min(agents.Count, MAXCARDS);
        int h = P(HEAD) + (n > 0 ? n * P(CARD + GAP) + P(PAD) - P(GAP) + P(4) : 0) + (agents.Count > MAXCARDS && !collapsed ? P(18) : 0);
        if (Height != h) Height = h;
        using (GraphicsPath gp = Round(new Rectangle(0, 0, Width, Height), P(12))) { Region = new Region(gp); }
        if (!moved) { Rectangle wa = Screen.PrimaryScreen.WorkingArea; Location = new Point(wa.Right - Width - P(18), wa.Bottom - Height - P(18)); }
    }

    static GraphicsPath Round(Rectangle r, int rad) {
        GraphicsPath p = new GraphicsPath(); int d = rad * 2;
        p.AddArc(r.X, r.Y, d, d, 180, 90); p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90); p.AddArc(r.X, r.Bottom - d, d, d, 90, 90); p.CloseFigure(); return p;
    }

    static void Txt(Graphics g, string s, Font f, Color c, Rectangle r, TextFormatFlags extra) {
        TextRenderer.DrawText(g, s, f, r, c, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis |
            TextFormatFlags.NoPrefix | TextFormatFlags.SingleLine | extra);
    }

    static string Elapsed(double s) { if (s < 0) s = 0; return s < 60 ? string.Format("{0:0}s", s) : string.Format("{0}m {1:00}s", (int)(s / 60), (int)(s % 60)); }

    static void StatusOf(HudAgent a, double now, out string label, out Color col) {
        if (a.Status == "running") {
            if (now - a.Seen > 300) { label = "Stalled"; col = C("#6B7280"); return; }
            label = "Running"; col = C("#3B82F6"); return;
        }
        if (a.Mcp) { label = "Idle"; col = C("#6B7280"); return; }
        switch (a.Result) {
            case "PASS": label = "Passed"; col = C("#22C55E"); return;
            case "WARN": label = "Warning"; col = C("#F59E0B"); return;
            case "FAIL": label = "Failed"; col = C("#EF4444"); return;
            case "BLOCKED": label = "Blocked"; col = C("#DC2626"); return;
            default: label = "Done"; col = C("#22C55E"); return;
        }
    }

    protected override void OnPaint(PaintEventArgs e) {
        Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias; g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
        double now = Now();
        using (Pen border = new Pen(C("#2A2E37"), 1f)) using (GraphicsPath gp = Round(new Rectangle(0, 0, Width - 1, Height - 1), P(12))) g.DrawPath(border, gp);

        // header: logo, title, live counts, collapse + close
        Rectangle logo = new Rectangle(P(14), P(12), P(20), P(20));
        using (LinearGradientBrush lb = new LinearGradientBrush(logo, C("#8B5CF6"), C("#06B6D4"), 45f)) g.FillEllipse(lb, logo);
        using (Pen wp = new Pen(Color.White, 1.6f * S)) {
            g.DrawLine(wp, logo.X + P(6), logo.Y + P(10), logo.X + P(9), logo.Y + P(13));
            g.DrawLine(wp, logo.X + P(9), logo.Y + P(13), logo.X + P(14), logo.Y + P(7));
        }
        Txt(g, "InfraCortex", fTitle, C("#E5E7EB"), new Rectangle(P(42), 0, P(140), P(HEAD)), TextFormatFlags.Default);
        int running = agents.Count(a => a.Status == "running"), done = agents.Count - running;
        string counts = running > 0 ? (done > 0 ? running + " running" + DOT + done + " done" : running + " running") : done + " done";
        Txt(g, counts, fSmall, C("#9CA3AF"), new Rectangle(P(170), 0, P(150), P(HEAD)), TextFormatFlags.Right);
        collapseBtn = new Rectangle(Width - P(60), P(12), P(20), P(20)); closeBtn = new Rectangle(Width - P(34), P(12), P(20), P(20));
        using (Pen ip = new Pen(C("#9CA3AF"), 1.4f * S)) {
            int cy = collapseBtn.Y + collapseBtn.Height / 2;
            if (collapsed) { g.DrawLine(ip, collapseBtn.X + P(5), cy + P(2), collapseBtn.X + P(10), cy - P(3)); g.DrawLine(ip, collapseBtn.X + P(10), cy - P(3), collapseBtn.X + P(15), cy + P(2)); }
            else { g.DrawLine(ip, collapseBtn.X + P(5), cy - P(2), collapseBtn.X + P(10), cy + P(3)); g.DrawLine(ip, collapseBtn.X + P(10), cy + P(3), collapseBtn.X + P(15), cy - P(2)); }
            g.DrawLine(ip, closeBtn.X + P(5), closeBtn.Y + P(5), closeBtn.Right - P(5), closeBtn.Bottom - P(5));
            g.DrawLine(ip, closeBtn.Right - P(5), closeBtn.Y + P(5), closeBtn.X + P(5), closeBtn.Bottom - P(5));
        }
        if (collapsed) return;

        int y = P(HEAD);
        for (int i = 0; i < Math.Min(agents.Count, MAXCARDS); i++) {
            DrawCard(g, agents[i], new Rectangle(P(PAD), y, Width - P(2 * PAD), P(CARD)), now);
            y += P(CARD + GAP);
        }
        if (agents.Count > MAXCARDS)
            Txt(g, "+" + (agents.Count - MAXCARDS) + " more", fSmall, C("#9CA3AF"), new Rectangle(P(PAD), y - P(4), Width - P(2 * PAD), P(16)), TextFormatFlags.HorizontalCenter);
    }

    void DrawCard(Graphics g, HudAgent a, Rectangle r, double now) {
        string[] m; if (!Meta.TryGetValue(a.Type, out m)) m = new[] { a.Type, "AG", "#F59E0B" };
        Color accent = C(m[2]); string label; Color sc; StatusOf(a, now, out label, out sc);
        bool run = a.Status == "running" && label == "Running";
        using (GraphicsPath gp = Round(r, P(10))) {
            using (SolidBrush b = new SolidBrush(C("#1C1F26"))) g.FillPath(b, gp);
            using (Pen p = new Pen(C("#272B34"), 1f)) g.DrawPath(p, gp);
        }

        // avatar with spinning ring (running) or status badge (finished)
        Rectangle av = new Rectangle(r.X + P(14), r.Y + P(14), P(38), P(38));
        using (SolidBrush ab = new SolidBrush(Color.FromArgb(48, accent))) g.FillEllipse(ab, av);
        Rectangle ring = Rectangle.Inflate(av, P(3), P(3));
        using (Pen track = new Pen(Color.FromArgb(50, accent), 2.5f * S)) g.DrawEllipse(track, ring);
        if (run) {
            using (Pen arc = new Pen(accent, 2.5f * S)) { arc.StartCap = LineCap.Round; arc.EndCap = LineCap.Round; g.DrawArc(arc, ring, angle, 100); }
        } else {
            using (Pen full = new Pen(Color.FromArgb(160, sc), 2.5f * S)) g.DrawEllipse(full, ring);
        }
        TextRenderer.DrawText(g, m[1], fAvatar, av, accent, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
        if (!run) {
            Rectangle bd = new Rectangle(av.Right - P(10), av.Bottom - P(10), P(15), P(15));
            using (SolidBrush bb = new SolidBrush(sc)) g.FillEllipse(bb, bd);
            using (Pen bp = new Pen(C("#1C1F26"), 2f * S)) g.DrawEllipse(bp, bd);
            using (Pen wp = new Pen(Color.White, 1.6f * S)) {
                if (label == "Passed" || label == "Done") {
                    g.DrawLine(wp, bd.X + P(4), bd.Y + P(8), bd.X + P(7), bd.Y + P(11)); g.DrawLine(wp, bd.X + P(7), bd.Y + P(11), bd.X + P(11), bd.Y + P(5));
                } else if (label == "Warning" || label == "Stalled" || label == "Idle") {
                    g.DrawLine(wp, bd.X + P(7.5f), bd.Y + P(4), bd.X + P(7.5f), bd.Y + P(9)); g.DrawLine(wp, bd.X + P(7.5f), bd.Y + P(11), bd.X + P(7.5f), bd.Y + P(11.5f));
                } else {
                    g.DrawLine(wp, bd.X + P(5), bd.Y + P(5), bd.X + P(10), bd.Y + P(10)); g.DrawLine(wp, bd.X + P(10), bd.Y + P(5), bd.X + P(5), bd.Y + P(10));
                }
            }
        }

        // name + status pill
        int tx = av.Right + P(14), tw = r.Right - tx - P(12);
        Size ps = TextRenderer.MeasureText(label, fPill);
        Rectangle pill = new Rectangle(r.Right - P(12) - ps.Width - P(14), r.Y + P(12), ps.Width + P(14), P(20));
        using (GraphicsPath pp = Round(pill, P(10))) { using (SolidBrush pb = new SolidBrush(Color.FromArgb(40, sc))) g.FillPath(pb, pp); }
        TextRenderer.DrawText(g, label, fPill, pill, sc, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
        Txt(g, m[0], fName, C("#F3F4F6"), new Rectangle(tx, r.Y + P(10), pill.X - tx - P(6), P(24)), TextFormatFlags.Default);

        // source line: app . project . elapsed ; then task (or final summary)
        double el = (a.Ended > 0 ? a.Ended : now) - a.Started;
        string src = string.Join(DOT, new[] { a.Source, a.Project, Elapsed(el) }.Where(x => !string.IsNullOrEmpty(x)).ToArray());
        Txt(g, src, fSmall, C("#9CA3AF"), new Rectangle(tx, r.Y + P(32), tw, P(18)), TextFormatFlags.Default);
        string task = !string.IsNullOrEmpty(a.Summary) && a.Ended > 0 ? a.Summary : a.Task;
        if (!string.IsNullOrEmpty(task)) Txt(g, task, fSmall, C("#D1D5DB"), new Rectangle(tx, r.Y + P(48), tw, P(18)), TextFormatFlags.Default);

        // last steps timeline (current step pulses)
        int sy = r.Y + P(68);
        List<HudStep> hs = a.History.Skip(Math.Max(0, a.History.Count - 2)).ToList();
        for (int i = 0; i < hs.Count; i++) {
            bool current = run && i == hs.Count - 1;
            Color dc = !hs[i].Ok ? C("#EF4444") : current ? accent : C("#4B5563");
            Rectangle dot = new Rectangle(r.X + P(16), sy + P(6), P(6), P(6));
            if (current) {
                int alpha = 60 + (int)(80 * Math.Abs(Math.Sin(angle * Math.PI / 180)));
                using (SolidBrush halo = new SolidBrush(Color.FromArgb(alpha, accent))) g.FillEllipse(halo, Rectangle.Inflate(dot, P(3), P(3)));
            }
            using (SolidBrush db = new SolidBrush(dc)) g.FillEllipse(db, dot);
            Txt(g, hs[i].Text, fMono, current ? C("#E5E7EB") : C("#9CA3AF"), new Rectangle(r.X + P(30), sy, r.Width - P(44), P(18)), TextFormatFlags.Default);
            sy += P(18);
        }

        // footer: metrics + activity bar
        string metrics = a.Steps + " steps" + (a.Errors > 0 ? DOT + a.Errors + (a.Errors == 1 ? " error" : " errors") + " recorded for learning" : "");
        Txt(g, metrics, fSmall, a.Errors > 0 ? C("#FCA5A5") : C("#6B7280"), new Rectangle(r.X + P(16), r.Bottom - P(26), r.Width - P(32), P(16)), TextFormatFlags.Default);
        Rectangle bar = new Rectangle(r.X + P(12), r.Bottom - P(6), r.Width - P(24), Math.Max(2, P(2)));
        using (SolidBrush tb = new SolidBrush(C("#262A33"))) g.FillRectangle(tb, bar);
        if (run) {
            int seg = bar.Width / 3, x = bar.X + (int)((bar.Width + seg) * (shimmer / 200f)) - seg;
            Rectangle sh = Rectangle.Intersect(bar, new Rectangle(x, bar.Y, seg, bar.Height));
            if (sh.Width > 0) using (SolidBrush sb = new SolidBrush(accent)) g.FillRectangle(sb, sh);
        } else {
            using (SolidBrush fb = new SolidBrush(Color.FromArgb(140, sc))) g.FillRectangle(fb, bar);
        }
    }

    public static void Run(string dir) {
        bool created;
        using (Mutex mx = new Mutex(true, "Local\\DevOpsAgentsHud", out created)) {
            if (!created) return;
            try { SetProcessDPIAware(); } catch { }
            Application.EnableVisualStyles();
            DevOpsHud f = new DevOpsHud(dir);
            f.FormClosed += delegate { try { File.Delete(Path.Combine(dir, "heartbeat")); } catch { } };
            Application.Run(f);
        }
    }
}
'@

[DevOpsHud]::Run($StateDir)
