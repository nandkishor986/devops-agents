#!/usr/bin/env python3
"""azdiagram.py — render Azure architecture diagrams with OFFICIAL Azure icons from a small typed JSON spec.

Why a spec: the model writes ~30 lines of JSON instead of Python; the script owns layout + icon mapping (token-lean, deterministic, diff-able in Git).

Usage:
  azdiagram.py render spec.json [-o out] [--format png|svg|pdf|drawio]   # drawio: no deps; others: pip install diagrams + Graphviz
  azdiagram.py from-tf <terraform_dir> > spec.json                 # draft a spec from azurerm_* resources
  azdiagram.py types                                               # list supported node types

Spec (v1):
{
  "title": "Hub-spoke AKS",
  "direction": "LR",                       # LR | TB
  "groups": [                               # nested boxes; kind only affects styling
    {"id": "sub", "label": "Prod subscription", "kind": "subscription", "children": [
      {"id": "hub", "label": "Hub VNet 10.0.0.0/16", "kind": "vnet", "nodes": ["fw", "bastion"]},
      {"id": "spoke", "label": "Spoke VNet 10.1.0.0/16", "kind": "vnet", "nodes": ["agw", "aks"]}
    ]}
  ],
  "nodes": [ {"id": "aks", "type": "aks", "label": "aks-prod"} ],
  "edges": [ {"from": "agw", "to": "aks", "label": "HTTPS", "style": "solid|dashed", "color": "#0078D4"} ]
}
"""
from __future__ import annotations

import importlib
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

# type -> (module, class) — verified against diagrams 0.25.x Azure provider (official Microsoft icon set)
TYPES: dict[str, tuple[str, str]] = {
    # compute / containers
    "aks": ("compute", "AKS"), "acr": ("containers", "ContainerRegistries"), "vm": ("compute", "VM"),
    "vmss": ("compute", "VMScaleSet"), "appservice": ("appservices", "AppServices"), "function": ("compute", "FunctionApps"),
    "containerapp": ("compute", "ContainerApps"), "aci": ("compute", "ContainerInstances"),
    # network
    "vnet": ("networking", "VirtualNetworks"), "subnet": ("network", "Subnets"), "nsg": ("networking", "NetworkSecurityGroups"),
    "appgw": ("networking", "ApplicationGateways"), "firewall": ("networking", "Firewalls"), "lb": ("networking", "LoadBalancers"),
    "pe": ("network", "PrivateEndpoint"), "dns": ("networking", "DNSZones"), "frontdoor": ("network", "FrontDoors"),
    "bastion": ("networking", "Bastions"), "vpngw": ("networking", "VirtualNetworkGateways"), "pip": ("networking", "PublicIpAddresses"),
    "nat": ("networking", "Nat"), "expressroute": ("networking", "ExpressrouteCircuits"), "trafficmanager": ("network", "TrafficManagerProfiles"),
    "privatelink": ("networking", "PrivateLink"), "routetable": ("networking", "RouteTables"),
    # data
    "storage": ("storage", "StorageAccounts"), "sql": ("database", "SQLDatabases"), "sqlserver": ("database", "SQLServers"),
    "cosmos": ("database", "CosmosDb"), "redis": ("databases", "CacheRedis"), "postgres": ("database", "DatabaseForPostgresqlServers"),
    "mysql": ("database", "DatabaseForMysqlServers"),
    # integration
    "apim": ("integration", "APIManagement"), "servicebus": ("integration", "ServiceBus"), "eventhub": ("analytics", "EventHubs"),
    "eventgrid": ("integration", "EventGridTopics"), "logicapp": ("integration", "LogicApps"),
    # security / identity
    "keyvault": ("security", "KeyVaults"), "identity": ("identity", "ManagedIdentities"), "entra": ("identity", "ActiveDirectory"),
    "defender": ("security", "Defender"), "sentinel": ("security", "Sentinel"),
    # ops / devops
    "loganalytics": ("analytics", "LogAnalyticsWorkspaces"), "monitor": ("monitor", "Monitor"), "appinsights": ("monitor", "ApplicationInsights"),
    "pipelines": ("devops", "Pipelines"), "repos": ("devops", "Repos"), "devops": ("devops", "Devops"),
    # governance / generic
    "rg": ("general", "ResourceGroups"), "subscription": ("general", "Subscriptions"), "users": ("general", "Usericon"),
    "openai": ("aimachinelearning", "AzureOpenai"),
}

# type -> draw.io built-in Azure icon (img/lib/azure2, official Microsoft icons) — verified against jgraph/drawio source
_A = "img/lib/azure2/"
DRAWIO: dict[str, str] = {
    "aks": "containers/Kubernetes_Services", "acr": "containers/Container_Registries", "vm": "compute/Virtual_Machine",
    "vmss": "compute/VM_Scale_Sets", "appservice": "app_services/App_Services", "function": "compute/Function_Apps",
    "containerapp": "other/Worker_Container_App", "aci": "containers/Container_Instances",
    "vnet": "networking/Virtual_Networks", "subnet": "networking/Subnet", "nsg": "networking/Network_Security_Groups",
    "appgw": "networking/Application_Gateways", "firewall": "networking/Firewalls", "lb": "networking/Load_Balancers",
    "pe": "networking/Private_Endpoint", "dns": "networking/DNS_Zones", "frontdoor": "networking/Front_Doors",
    "bastion": "networking/Bastions", "vpngw": "networking/Virtual_Network_Gateways", "pip": "networking/Public_IP_Addresses",
    "nat": "networking/NAT", "expressroute": "networking/ExpressRoute_Circuits", "trafficmanager": "networking/Traffic_Manager_Profiles",
    "privatelink": "networking/Private_Link", "routetable": "networking/Route_Tables",
    "storage": "storage/Storage_Accounts", "sql": "databases/SQL_Database", "sqlserver": "databases/SQL_Server",
    "cosmos": "databases/Azure_Cosmos_DB", "redis": "databases/Cache_Redis", "postgres": "databases/Azure_Database_PostgreSQL_Server",
    "mysql": "databases/Azure_Database_MySQL_Server",
    "apim": "integration/API_Management_Services", "servicebus": "integration/Service_Bus", "eventhub": "analytics/Event_Hubs",
    "eventgrid": "integration/Event_Grid_Topics", "logicapp": "integration/Logic_Apps",
    "keyvault": "security/Key_Vaults", "identity": "identity/Managed_Identities", "entra": "other/Entra_Identity",
    "defender": "security/Security_Center", "sentinel": "security/Azure_Sentinel",
    "loganalytics": "analytics/Log_Analytics_Workspaces", "monitor": "management_governance/Monitor",
    "appinsights": "devops/Application_Insights", "pipelines": "devops/Azure_DevOps", "repos": "general/TFS_VC_Repository",
    "devops": "devops/Azure_DevOps", "rg": "general/Resource_Groups", "subscription": "general/Subscriptions",
    "users": "identity/Users", "openai": "ai_machine_learning/Azure_OpenAI",
}
DRAWIO_GROUP = {
    "subscription": "fillColor=#F3F9FD;strokeColor=#0078D4;",
    "rg": "fillColor=#FFFFFF;strokeColor=#7A7A7A;dashed=1;",
    "vnet": "fillColor=#EAF4EA;strokeColor=#107C10;",
    "subnet": "fillColor=#FFFFFF;strokeColor=#107C10;dashed=1;",
    "cluster": "fillColor=#EEF3FB;strokeColor=#326CE5;",
    "onprem": "fillColor=#F5F5F5;strokeColor=#505050;",
    "box": "fillColor=none;strokeColor=#999999;",
}

# azurerm resource type -> spec type (for from-tf)
TF_MAP: dict[str, str] = {
    "azurerm_kubernetes_cluster": "aks", "azurerm_container_registry": "acr", "azurerm_linux_virtual_machine": "vm",
    "azurerm_windows_virtual_machine": "vm", "azurerm_linux_virtual_machine_scale_set": "vmss", "azurerm_linux_web_app": "appservice",
    "azurerm_windows_web_app": "appservice", "azurerm_linux_function_app": "function", "azurerm_container_app": "containerapp",
    "azurerm_virtual_network": "vnet", "azurerm_subnet": "subnet", "azurerm_network_security_group": "nsg",
    "azurerm_application_gateway": "appgw", "azurerm_firewall": "firewall", "azurerm_lb": "lb", "azurerm_private_endpoint": "pe",
    "azurerm_private_dns_zone": "dns", "azurerm_dns_zone": "dns", "azurerm_cdn_frontdoor_profile": "frontdoor", "azurerm_bastion_host": "bastion",
    "azurerm_virtual_network_gateway": "vpngw", "azurerm_public_ip": "pip", "azurerm_nat_gateway": "nat", "azurerm_route_table": "routetable",
    "azurerm_storage_account": "storage", "azurerm_mssql_server": "sqlserver", "azurerm_mssql_database": "sql", "azurerm_cosmosdb_account": "cosmos",
    "azurerm_redis_cache": "redis", "azurerm_postgresql_flexible_server": "postgres", "azurerm_mysql_flexible_server": "mysql",
    "azurerm_api_management": "apim", "azurerm_servicebus_namespace": "servicebus", "azurerm_eventhub_namespace": "eventhub",
    "azurerm_eventgrid_topic": "eventgrid", "azurerm_logic_app_workflow": "logicapp", "azurerm_key_vault": "keyvault",
    "azurerm_user_assigned_identity": "identity", "azurerm_log_analytics_workspace": "loganalytics", "azurerm_application_insights": "appinsights",
    "azurerm_resource_group": "rg", "azurerm_cognitive_account": "openai",
}
GROUP_STYLE = {
    "subscription": {"bgcolor": "#F3F9FD", "pencolor": "#0078D4", "style": "rounded"},
    "rg": {"bgcolor": "#FFFFFF", "pencolor": "#7A7A7A", "style": "rounded,dashed"},
    "vnet": {"bgcolor": "#EAF4EA", "pencolor": "#107C10", "style": "rounded"},
    "subnet": {"bgcolor": "#FFFFFF", "pencolor": "#107C10", "style": "dashed"},
    "cluster": {"bgcolor": "#EEF3FB", "pencolor": "#326CE5", "style": "rounded"},
    "onprem": {"bgcolor": "#F5F5F5", "pencolor": "#505050", "style": "rounded"},
    "box": {},
}
ID = re.compile(r"^[a-zA-Z][a-zA-Z0-9_-]{0,63}$")


@dataclass(frozen=True)
class NodeSpec:
    id: str
    type: str
    label: str


@dataclass(frozen=True)
class EdgeSpec:
    src: str
    dst: str
    label: str = ""
    style: str = "solid"
    color: str = "#444444"


@dataclass
class GroupSpec:
    id: str
    label: str
    kind: str = "box"
    nodes: list[str] = field(default_factory=list)
    children: list["GroupSpec"] = field(default_factory=list)


@dataclass
class Spec:
    title: str
    direction: str
    nodes: dict[str, NodeSpec]
    edges: list[EdgeSpec]
    groups: list[GroupSpec]


class SpecError(ValueError):
    pass


def _group(g: dict, path: str) -> GroupSpec:
    for k in g:
        if k not in {"id", "label", "kind", "nodes", "children"}:
            raise SpecError(f"{path}: unknown key {k!r}")
    kind = g.get("kind", "box")
    if kind not in GROUP_STYLE:
        raise SpecError(f"{path}.kind {kind!r} not in {list(GROUP_STYLE)}")
    return GroupSpec(id=g.get("id", path), label=g["label"], kind=kind, nodes=list(g.get("nodes", [])),
                     children=[_group(c, f"{path}.children[{i}]") for i, c in enumerate(g.get("children", []))])


def parse(doc: dict) -> Spec:
    errs: list[str] = []
    nodes: dict[str, NodeSpec] = {}
    for i, n in enumerate(doc.get("nodes", [])):
        nid, t = n.get("id", ""), n.get("type", "")
        if not ID.match(nid):
            errs.append(f"nodes[{i}].id {nid!r} invalid")
        if t not in TYPES:
            errs.append(f"nodes[{i}].type {t!r} unknown (run: azdiagram.py types)")
        if nid in nodes:
            errs.append(f"nodes[{i}].id {nid!r} duplicate")
        nodes[nid] = NodeSpec(nid, t, n.get("label", nid))
    edges = []
    for i, e in enumerate(doc.get("edges", [])):
        for end in ("from", "to"):
            if e.get(end) not in nodes:
                errs.append(f"edges[{i}].{end} {e.get(end)!r} not a node id")
        if e.get("style", "solid") not in ("solid", "dashed", "dotted", "bold"):
            errs.append(f"edges[{i}].style invalid")
        edges.append(EdgeSpec(e.get("from", ""), e.get("to", ""), e.get("label", ""), e.get("style", "solid"), e.get("color", "#444444")))
    try:
        groups = [_group(g, f"groups[{i}]") for i, g in enumerate(doc.get("groups", []))]
    except (SpecError, KeyError) as ex:
        errs.append(str(ex))
        groups = []
    placed: list[str] = []

    def walk(gs: list[GroupSpec]) -> None:
        for g in gs:
            for nid in g.nodes:
                if nid not in nodes:
                    errs.append(f"group {g.id}: node {nid!r} not declared")
                placed.append(nid)
            walk(g.children)
    walk(groups)
    dup = {x for x in placed if placed.count(x) > 1}
    if dup:
        errs.append(f"nodes placed in more than one group: {sorted(dup)}")
    if doc.get("direction", "LR") not in ("LR", "TB", "RL", "BT"):
        errs.append("direction must be LR|TB|RL|BT")
    if errs:
        raise SpecError("\n".join(errs))
    return Spec(doc.get("title", "Architecture"), doc.get("direction", "LR"), nodes, edges, groups)


def render(spec: Spec, out: str, fmt: str) -> str:
    from diagrams import Cluster, Diagram, Edge  # lazy: only needed for render
    built: dict[str, object] = {}

    def make(nid: str):
        n = spec.nodes[nid]
        mod, cls = TYPES[n.type]
        built[nid] = getattr(importlib.import_module(f"diagrams.azure.{mod}"), cls)(n.label)

    def walk(gs: list[GroupSpec]) -> None:
        for g in gs:
            with Cluster(g.label, graph_attr={**GROUP_STYLE[g.kind], "fontsize": "13", "fontname": "Segoe UI,Helvetica"}):
                for nid in g.nodes:
                    make(nid)
                walk(g.children)

    attrs = {"fontsize": "18", "fontname": "Segoe UI,Helvetica", "pad": "0.4", "nodesep": "0.7", "ranksep": "1.0", "splines": "spline"}
    with Diagram(spec.title, filename=out, outformat=fmt, show=False, direction=spec.direction, graph_attr=attrs,
                 node_attr={"fontsize": "11", "fontname": "Segoe UI,Helvetica"}):
        walk(spec.groups)
        for nid in spec.nodes:
            if nid not in built:
                make(nid)
        for e in spec.edges:
            built[e.src] >> Edge(label=e.label, style=e.style, color=e.color, fontsize="10") >> built[e.dst]
    return f"{out}.{fmt}"


def render_drawio(spec: Spec, out: str) -> str:
    """Write an editable, uncompressed .drawio file: nested containers + official Azure icons (no dependencies)."""
    import html
    import math
    import xml.etree.ElementTree as ET
    ICON, PAD, GAP, FONT, LINE_H = 50, 20, 24, 11, 15
    SLOT_W = 180                       # wide enough that a wrapped label never reaches the neighbouring icon
    LBL_W = SLOT_W - 16
    CHAR_W = FONT * 0.6                # rough average glyph width (Helvetica 11px)
    MAX_W = 1300

    def lines(text: str, width: float, char_w: float = CHAR_W) -> int:
        """Estimated rendered line count after word-wrap at `width` px ('\\n' = hard break)."""
        return sum(max(1, math.ceil(len(seg) * char_w / width)) for seg in (text or " ").split("\n"))

    def label(text: str) -> str:       # html=1 labels: escape, and make '\n' a real line break
        return html.escape(text or "").replace("\n", "<br>")

    # one row height for the whole grid, sized to the tallest label → labels can't run into the row below
    SLOT_H = 10 + ICON + 6 + LINE_H * max([lines(n.label, LBL_W) for n in spec.nodes.values()] or [1]) + 14

    def head(g: GroupSpec, inner_w: float) -> float:
        return 12 + 17 * lines(g.label, inner_w - 20, 13 * 0.62)

    def rows(items: list[tuple[float, float]]) -> list[list[int]]:
        out, cur, w = [], [], 0.0
        for i, (iw, _) in enumerate(items):
            if cur and w + GAP + iw > MAX_W:
                out.append(cur); cur, w = [], 0.0
            w += (GAP if cur else 0) + iw
            cur.append(i)
        return out + ([cur] if cur else [])

    def size(g: GroupSpec) -> tuple[float, float]:
        per_row = max(1, int(MAX_W // SLOT_W))
        nrows = -(-len(g.nodes) // per_row)
        nw = min(len(g.nodes), per_row) * SLOT_W
        nh = nrows * SLOT_H
        cs = [size(c) for c in g.children]
        rw = rh = 0.0
        for r in rows(cs):
            rw = max(rw, sum(cs[i][0] for i in r) + GAP * (len(r) - 1))
            rh += max(cs[i][1] for i in r) + GAP
        rh = max(rh - GAP, 0)
        w = max(nw, rw, 260) + 2 * PAD
        h = head(g, w) + nh + (GAP if g.nodes and cs else 0) + rh + PAD
        return w, h

    mxfile = ET.Element("mxfile", host="azdiagram")
    diagram = ET.SubElement(mxfile, "diagram", id="arch", name=spec.title)
    model = ET.SubElement(diagram, "mxGraphModel", grid="1", gridSize="10", guides="1", tooltips="1", connect="1",
                          arrows="1", fold="1", page="1", pageScale="1", math="0", shadow="0")
    root = ET.SubElement(model, "root")
    ET.SubElement(root, "mxCell", id="0")
    ET.SubElement(root, "mxCell", id="1", parent="0")

    def cell(cid: str, value: str, style: str, parent: str, x: float, y: float, w: float, h: float) -> None:
        c = ET.SubElement(root, "mxCell", id=cid, value=value, style=style, vertex="1", parent=parent)
        ET.SubElement(c, "mxGeometry", x=str(x), y=str(y), width=str(w), height=str(h), **{"as": "geometry"})

    def icon(nid: str, parent: str, x: float, y: float) -> None:
        n = spec.nodes[nid]
        style = (f"image;aspect=fixed;html=1;points=[];align=center;fontSize={FONT};verticalLabelPosition=bottom;"
                 f"verticalAlign=top;labelPosition=center;whiteSpace=wrap;labelWidth={LBL_W};"
                 f"image={_A}{DRAWIO[n.type]}.svg;")
        cell(nid, label(n.label), style, parent, x + (SLOT_W - ICON) / 2, y + 10, ICON, ICON)

    def place(g: GroupSpec, parent: str, x: float, y: float) -> None:
        w, h = size(g)
        gid = f"grp_{g.id}"
        style = ("rounded=1;arcSize=4;whiteSpace=wrap;html=1;container=1;collapsible=0;verticalAlign=top;align=left;"
                 f"spacingLeft=10;spacingTop=4;fontStyle=1;fontSize=13;{DRAWIO_GROUP[g.kind]}")
        cell(gid, label(g.label), style, parent, x, y, w, h)
        hd = head(g, w)
        per_row = max(1, int(MAX_W // SLOT_W))
        for i, nid in enumerate(g.nodes):
            icon(nid, gid, PAD + (i % per_row) * SLOT_W, hd + (i // per_row) * SLOT_H)
        cy = hd + (-(-len(g.nodes) // per_row) * SLOT_H + GAP if g.nodes else 0)
        cs = [size(c) for c in g.children]
        for r in rows(cs):
            cx = PAD
            for i in r:
                place(g.children[i], gid, cx, cy)
                cx += cs[i][0] + GAP
            cy += max(cs[i][1] for i in r) + GAP

    grouped: set[str] = set()

    def collect(gs: list[GroupSpec]) -> None:
        for g in gs:
            grouped.update(g.nodes)
            collect(g.children)
    collect(spec.groups)
    loose = [n for n in spec.nodes if n not in grouped]
    for i, nid in enumerate(loose):
        icon(nid, "1", 20, 40 + i * (SLOT_H + 20))
    x = 20 + (SLOT_W + 40 if loose else 0)
    for g in spec.groups:
        place(g, "1", x, 40)
        x += size(g)[0] + 40
    dash = {"solid": "", "bold": "strokeWidth=2;", "dashed": "dashed=1;", "dotted": "dashed=1;dashPattern=1 4;"}
    for i, e in enumerate(spec.edges):
        c = ET.SubElement(root, "mxCell", id=f"e{i}", value=label(e.label), edge="1", parent="1", source=e.src,
                          target=e.dst,
                          style=f"edgeStyle=orthogonalEdgeStyle;rounded=1;html=1;fontSize=10;endArrow=block;endFill=1;"
                                f"labelBackgroundColor=#FFFFFF;fontColor=#333333;strokeColor={e.color};{dash[e.style]}")
        ET.SubElement(c, "mxGeometry", relative="1", **{"as": "geometry"})
    path = f"{out}.drawio"
    ET.ElementTree(mxfile).write(path, encoding="utf-8", xml_declaration=False)
    return path


def from_tf(d: str) -> dict:
    res = re.compile(r'^\s*resource\s+"(azurerm_[a-z0-9_]+)"\s+"([a-zA-Z0-9_-]+)"', re.M)
    nodes, seen = [], set()
    for f in sorted(Path(d).rglob("*.tf")):
        if ".terraform" in f.parts:
            continue
        for rtype, name in res.findall(f.read_text(encoding="utf-8", errors="ignore")):
            t = TF_MAP.get(rtype)
            nid = re.sub(r"[^a-zA-Z0-9_-]", "_", f"{t}_{name}") if t else None
            if t and nid not in seen and t not in ("subnet", "rg"):
                seen.add(nid)
                nodes.append({"id": nid, "type": t, "label": name.replace("_", "-")})
    return {"title": f"Architecture ({Path(d).resolve().name})", "direction": "LR",
            "groups": [{"id": "draft", "label": "TODO: split into subscription / vnet / subnet groups", "kind": "subscription",
                        "nodes": [n["id"] for n in nodes]}],
            "nodes": nodes, "edges": []}


def main(argv: list[str]) -> int:
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    cmd = argv[0]
    if cmd == "types":
        for k, (m, c) in sorted(TYPES.items()):
            print(f"{k:15} diagrams.azure.{m}.{c}")
        return 0
    if cmd == "from-tf" and len(argv) > 1:
        print(json.dumps(from_tf(argv[1]), indent=2))
        return 0
    if cmd == "render" and len(argv) > 1:
        src = argv[1]
        out = argv[argv.index("-o") + 1] if "-o" in argv else Path(src).with_suffix("").as_posix()
        fmt = argv[argv.index("--format") + 1] if "--format" in argv else "png"
        try:
            spec = parse(json.loads(Path(src).read_text(encoding="utf-8")))
        except (SpecError, ValueError, KeyError) as e:
            print(f"SPEC ERROR\n{e}", file=sys.stderr)
            return 1
        if fmt == "drawio":
            print(render_drawio(spec, out))
            return 0
        try:
            print(render(spec, out, fmt))
        except ImportError:
            print("diagrams not installed: pip install diagrams  (+ Graphviz: winget install graphviz | brew install graphviz | apt install graphviz)", file=sys.stderr)
            return 2
        except AttributeError as e:
            print(f"icon class missing in installed diagrams version: {e} — upgrade: pip install -U diagrams", file=sys.stderr)
            return 2
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
