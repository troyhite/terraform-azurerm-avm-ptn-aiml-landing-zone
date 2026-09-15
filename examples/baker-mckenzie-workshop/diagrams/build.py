"""Generate the two workshop draw.io diagrams with embedded official Azure icons."""
from pathlib import Path
import base64
import xml.etree.ElementTree as ET

ICONS = Path(r"C:\Users\troyhite\.scout\copilot\session-state\3f4452b5-5300-490b-9ba6-f3d6eab68a35\files\azure-icons\extracted")
OUT = Path(r"C:\dev\terraform-azurerm-avm-ptn-aiml-landing-zone\examples\baker-mckenzie-workshop\diagrams")

ASSETS = {
    "apim":     ("10042-icon-service-API-Management-Services.svg", "API Management"),
    "foundry":  ("035746832-icon-service-AI-Foundry.svg", "AI Foundry"),
    "project":  ("036509415-icon-service-Foundry-Project.svg", "Foundry project"),
    "models":   ("038470614-icon-service-Foundry-Models.svg", "Models"),
    "search":   ("10044-icon-service-Cognitive-Search.svg", "AI Search"),
    "storage":  ("10086-icon-service-Storage-Accounts.svg", "Storage"),
    "kv":       ("10245-icon-service-Key-Vaults.svg", "Key Vault"),
    "policy":   ("10316-icon-service-Policy.svg", "Azure Policy"),
    "sub":      ("10002-icon-service-Subscriptions.svg", "Subscription"),
    "vnet":     ("10061-icon-service-Virtual-Networks.svg", "Virtual network"),
    "rbac":     ("10340-icon-service-Entra-Identity-Roles-and-Administrators.svg", "Entra RBAC"),
    "mi":       ("10227-icon-service-Managed-Identities.svg", "Managed identity"),
    "safety":   ("03390-icon-service-Content-Safety.svg", "Content Safety"),
    "landing":  ("029636048-icon-service-Landing-Zone.svg", "Landing zone"),
    "law":      ("00009-icon-service-Log-Analytics-Workspaces.svg", "Log Analytics"),
    "plink":    ("00427-icon-service-Private-Link.svg", "Private Link"),
    "cost":     ("00004-icon-service-Cost-Management-and-Billing.svg", "Cost Management"),
    "rg":       ("10007-icon-service-Resource-Groups.svg", "Resource group"),
}
DATA = {}
for key, (fn, _) in ASSETS.items():
    m = sorted(ICONS.rglob(fn))
    if not m:
        raise FileNotFoundError(fn)
    raw = m[0].read_bytes()
    ET.fromstring(raw)  # validate SVG
    DATA[key] = base64.b64encode(raw).decode("ascii")

INK = "#172B42"
BLUE = "#0078D4"
TEAL = "#007F86"
PALE = "#EDF5FC"
NEUTRAL = "#F5F7FA"
ROSE = "#B11F4B"
MUTED = "#536779"


class Draw:
    def __init__(self, name, w, h):
        self.name = name
        self.file = ET.Element("mxfile", host="Electron", version="24.7.17")
        d = ET.SubElement(self.file, "diagram", id=name, name=name)
        self.model = ET.SubElement(d, "mxGraphModel", dx=str(w), dy=str(h), grid="1",
                                   gridSize="10", guides="1", connect="1", arrows="1", fold="1",
                                   page="1", pageScale="1", pageWidth=str(w), pageHeight=str(h),
                                   math="0", shadow="0", background="#FFFFFF")
        self.root = ET.SubElement(self.model, "root")
        ET.SubElement(self.root, "mxCell", id="0")
        ET.SubElement(self.root, "mxCell", id="1", parent="0")
        self.n = 0

    def _id(self, hint):
        self.n += 1
        return f"{hint}{self.n}"

    def box(self, x, y, w, h, label, fill=NEUTRAL, stroke="#C5D8E9", parent="1",
            font=13, bold=1, dashed=0, rounded=1, valign="middle", fontcolor=INK):
        i = self._id("b")
        style = (f"rounded={rounded};whiteSpace=wrap;html=1;fillColor={fill};strokeColor={stroke};"
                 f"strokeWidth=1.5;fontColor={fontcolor};fontSize={font};fontStyle={bold};"
                 f"verticalAlign={valign};arcSize=8;dashed={dashed};")
        c = ET.SubElement(self.root, "mxCell", id=i, value=label, style=style, vertex="1", parent=parent)
        ET.SubElement(c, "mxGeometry", x=str(x), y=str(y), width=str(w), height=str(h),
                      attrib={"as": "geometry"})
        return i

    def container(self, x, y, w, h, label, stroke=BLUE, fill="none", parent="1", font=14, dashed=0):
        i = self._id("g")
        style = (f"rounded=1;whiteSpace=wrap;html=1;fillColor={fill};strokeColor={stroke};"
                 f"strokeWidth=2;fontColor={INK};fontSize={font};fontStyle=1;verticalAlign=top;"
                 f"align=left;spacingLeft=12;spacingTop=8;arcSize=6;dashed={dashed};")
        c = ET.SubElement(self.root, "mxCell", id=i, value=label, style=style, vertex="1", parent=parent)
        ET.SubElement(c, "mxGeometry", x=str(x), y=str(y), width=str(w), height=str(h),
                      attrib={"as": "geometry"})
        return i

    def icon(self, key, x, y, parent="1", size=44, label=None):
        i = self._id("i")
        lbl = label if label is not None else ASSETS[key][1]
        style = (f"shape=image;verticalLabelPosition=bottom;labelBackgroundColor=none;"
                 f"verticalAlign=top;imageAspect=0;aspect=fixed;image=data:image/svg+xml,{DATA[key]};"
                 f"fontSize=11;fontColor={INK};")
        c = ET.SubElement(self.root, "mxCell", id=i, value=lbl, style=style, vertex="1", parent=parent)
        ET.SubElement(c, "mxGeometry", x=str(x), y=str(y), width=str(size), height=str(size),
                      attrib={"as": "geometry"})
        return i

    def text(self, x, y, w, h, label, font=13, bold=0, color=INK, align="left"):
        i = self._id("t")
        style = (f"text;html=1;whiteSpace=wrap;strokeColor=none;fillColor=none;align={align};"
                 f"verticalAlign=top;fontColor={color};fontSize={font};fontStyle={bold};")
        c = ET.SubElement(self.root, "mxCell", id=i, value=label, style=style, vertex="1", parent="1")
        ET.SubElement(c, "mxGeometry", x=str(x), y=str(y), width=str(w), height=str(h),
                      attrib={"as": "geometry"})
        return i

    def edge(self, src, dst, label="", dashed=0, color=TEAL, style_extra=""):
        i = self._id("e")
        style = (f"edgeStyle=orthogonalEdgeStyle;rounded=1;html=1;endArrow=block;endFill=1;"
                 f"strokeColor={color};strokeWidth=2;fontSize=11;fontColor={MUTED};"
                 f"labelBackgroundColor=#FFFFFF;dashed={dashed};{style_extra}")
        c = ET.SubElement(self.root, "mxCell", id=i, value=label, style=style, edge="1", parent="1",
                          source=src, target=dst)
        g = ET.SubElement(c, "mxGeometry", relative="1", attrib={"as": "geometry"})
        return i

    def save(self):
        ET.indent(self.file, space="  ")
        p = OUT / f"{self.name}.drawio"
        p.write_bytes(ET.tostring(self.file, encoding="utf-8", xml_declaration=True))
        print(f"wrote {p.name}")


# =====================================================================
# Diagram 1: Hub-and-spoke AI gateway
# =====================================================================
d = Draw("hub-and-spoke-gateway", 1240, 940)
d.text(40, 24, 1160, 40, "Baker McKenzie - AI Gateway Landing Zone", font=22, bold=1)
d.text(40, 60, 1160, 24, "One governed front door (hub APIM) fronting many private Foundry sandboxes, one per team / subscription.",
       font=13, color=MUTED)

# Clients
d.box(500, 108, 240, 54, "Team apps / clients\n(per-team key + Entra auth)", fill=PALE, stroke=BLUE, font=12)

# Hub subscription container
hub = d.container(360, 200, 520, 210, "HUB subscription (platform / homelab)", stroke=INK)
d.icon("apim", 400, 250, parent=hub, size=46, label="Azure API Management (StandardV2)")
d.box(470, 250, 360, 130, "", fill="none", stroke="none", parent=hub)
d.text(470, 250, 380, 20, "Per team: API + product + subscription key", font=12, bold=1)
d.text(470, 272, 380, 20, "azure-openai-token-limit  (fair-use quota)", font=11, color=MUTED)
d.text(470, 292, 380, 20, "emit-token-metric  ->  showback", font=11, color=MUTED)
d.text(470, 312, 380, 20, "managed-identity auth to each Foundry", font=11, color=MUTED)
d.icon("law", 400, 330, parent=hub, size=40, label="Hub Log Analytics (token metrics)")

# Three sandbox subscriptions
teams = [("applied-ai", "contract-analysis"), ("client-innovation", "matter-triage"), ("danielle", "model-eval")]
xs = [70, 470, 870]
sandbox_ids = []
for (team, uc), x in zip(teams, xs):
    live = team == "applied-ai"
    g = d.container(x, 520, 300, 350,
                    f"Sandbox sub - {team}" + ("   (LIVE demo)" if live else "   (config + diagram)"),
                    stroke=BLUE if live else MUTED, dashed=0 if live else 1)
    d.icon("landing", x + 20, 552, size=34, label="AI Landing Zone")
    fnd = d.icon("foundry", x + 20, 618, size=40, label="Foundry (private)")
    d.icon("project", x + 120, 618, size=36, label="Project")
    d.icon("models", x + 210, 618, size=36, label="gpt-4.1 + embeddings")
    d.icon("search", x + 20, 712, size=34, label="AI Search")
    d.icon("storage", x + 110, 712, size=34, label="Storage")
    d.icon("kv", x + 200, 712, size=34, label="Key Vault")
    d.icon("plink", x + 20, 796, size=30, label="Private endpoints")
    d.icon("policy", x + 130, 796, size=30, label="Model allow-list policy")
    d.icon("cost", x + 240, 796, size=30, label="Budget")
    sandbox_ids.append(fnd)

# Edges
d.edge(d.box(500, 108, 0, 0, "", fill="none", stroke="none"), None) if False else None
# client -> apim (use the client box id)
# rebuild: get client + apim ids
# (simpler: connect via known ids captured)
d.save()

# The edges above need real ids; rebuild diagram 1 cleanly with captured ids.
d = Draw("hub-and-spoke-gateway", 1240, 980)
d.text(40, 20, 1160, 30, "Baker McKenzie - Secure Foundry sandboxes + AI gateway", font=22, bold=1)
d.text(40, 54, 1160, 24, "Two access planes: developers build directly in their sandbox (Entra + RBAC); apps consume models at runtime through the hub gateway.",
       font=13, color=MUTED)

# Developer plane (left) and runtime plane (right)
devs = d.box(40, 96, 250, 62, "DEVELOPER TEAMS (humans)\nEntra + least-priv RBAC\nvia Cloud PC / Bastion / VPN",
             fill="#E9F3E6", stroke="#137347", font=11)
clients = d.box(950, 96, 250, 62, "APPS / SHARED CONSUMERS\n(runtime) - per-team key + Entra",
                fill=PALE, stroke=BLUE, font=11)

hub = d.container(470, 92, 430, 168, "HUB sub - runtime plane", stroke=INK)
apim = d.icon("apim", 496, 132, size=46, label="Azure API Management (StandardV2)")
d.text(556, 130, 330, 16, "per-team key + token-limit (fair use)", font=11, bold=1)
d.text(556, 150, 330, 16, "emit-token-metric -> showback", font=11, color=MUTED)
d.text(556, 170, 330, 16, "managed-identity auth to Foundry", font=11, color=MUTED)
law = d.icon("law", 496, 205, size=34, label="Hub Log Analytics (token metrics)")
d.edge(clients, apim, "https + key")

teams2 = teams
sandbox_fnds = []
for (team, uc), x in zip(teams2, xs):
    live = team == "applied-ai"
    g = d.container(x, 560, 300, 360,
                    f"Sandbox sub - {team}" + ("   (LIVE)" if live else "   (config + diagram)"),
                    stroke="#137347" if live else MUTED, dashed=0 if live else 1)
    d.icon("landing", x + 18, 592, size=32, label="AI Landing Zone")
    fnd = d.icon("foundry", x + 18, 660, size=44, label="Foundry (private)\ndevelopers build here")
    d.icon("project", x + 128, 660, size=36, label="Project")
    d.icon("models", x + 218, 660, size=36, label="gpt-4.1 + embed")
    d.icon("search", x + 18, 762, size=34, label="AI Search")
    d.icon("storage", x + 110, 762, size=34, label="Storage")
    d.icon("kv", x + 202, 762, size=34, label="Key Vault")
    d.icon("plink", x + 18, 846, size=30, label="Private endpoints")
    d.icon("policy", x + 128, 846, size=30, label="Model policy")
    d.icon("cost", x + 236, 846, size=30, label="Budget")
    sandbox_fnds.append(fnd)
    # Developer (build) plane: secure, direct into Foundry.
    d.edge(devs, fnd, "Entra + RBAC\n(build plane)" if live else "", dashed=0 if live else 1,
           color="#137347" if live else MUTED)
    # Runtime plane: gateway to Foundry models.
    d.edge(apim, fnd, "private runtime\n(VNet integ.+peering+DNS)" if live else "", dashed=0 if live else 1,
           color=TEAL if live else MUTED)
d.text(40, 936, 1160, 34,
       "Green = developer/build plane (humans into Foundry, Entra + RBAC). Teal = application/runtime plane (apps -> hub gateway -> models). "
       "Solid = live; dashed = config + diagram. Foundry stays private on both planes.",
       font=11, color=MUTED)
d.save()

# =====================================================================
# Diagram 2: Experimentation -> production promotion lifecycle
# =====================================================================
d = Draw("promotion-lifecycle", 1280, 620)
d.text(40, 24, 1200, 30, "Experimentation to Production - governed promotion", font=22, bold=1)
d.text(40, 58, 1200, 24, "Same Terraform, two postures. Promotion is a governance decision backed by evidence, not a live migration.",
       font=13, color=MUTED)

steps = [
    ("intake", "1. Use-case intake", "Owner, data class,\nresidency, models, budget", "sub"),
    ("sandbox", "2. Governed sandbox", "environment = sandbox\nprivate Foundry, allow-list", "landing"),
    ("review", "3. Governance review", "security, data, RAI,\ncost, ownership evidence", "policy"),
    ("prod", "4. Production landing zone", "environment = production\nhardened, showback, alerts", "foundry"),
]
xs2 = [40, 350, 660, 970]
ids = []
for (sid, title, detail, icon), x in zip(steps, xs2):
    g = d.container(x, 150, 270, 250, title, stroke=BLUE)
    d.icon(icon, x + 110, 190, size=50)
    d.text(x + 16, 260, 238, 80, detail, font=12, color=INK, align="center")
    ids.append(g)
for a, b in zip(ids, ids[1:]):
    d.edge(a, b, "", color=TEAL)

d.box(40, 440, 1200, 60,
      "Guardrails travel with the sandbox at every stage: model allow-list (Azure Policy, audit -> deny),  "
      "Content Safety,  per-team RBAC (managed identity),  budget + token metrics (showback).",
      fill=PALE, stroke=BLUE, font=12, bold=0)
d.box(40, 520, 1200, 54,
      "Ethical walls / residency: DataZone model deployments keep data in-geo; Search / Storage / Key Vault are per team / per matter - never shared.",
      fill=NEUTRAL, stroke=ROSE, font=12, bold=0, fontcolor=INK)
d.save()

print("done")
