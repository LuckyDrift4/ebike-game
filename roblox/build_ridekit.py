"""
Pack roblox/RideKit/*.lua into roblox/RideKit.rbxmx: a Folder named "RideKit"
you insert into the bike Model in Roblox Studio (right-click the model ->
Insert from File..., or drag the file onto the model).

  Config, Rig, Physics, Pose  -> ModuleScripts
  BikeServer.server.lua       -> Script, RunContext = Server
  BikeClient.client.lua       -> Script, RunContext = Client (runs on every player, even inside Workspace)
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "RideKit")
OUT = os.path.join(HERE, "RideKit.rbxmx")

ITEMS = [
    ("ModuleScript", "Config", "Config.lua", None),
    ("ModuleScript", "Rig", "Rig.lua", None),
    ("ModuleScript", "Physics", "Physics.lua", None),
    ("ModuleScript", "Pose", "Pose.lua", None),
    ("Script", "BikeServer", "BikeServer.server.lua", 1),   # Enum.RunContext.Server
    ("Script", "BikeClient", "BikeClient.client.lua", 2),   # Enum.RunContext.Client
]


def item(cls, name, source, ref, run_context):
    assert "]]>" not in source, f"{name}: source may not contain ]]>"
    props = [f'<string name="Name">{name}</string>',
             f'<ProtectedString name="Source"><![CDATA[{source}]]></ProtectedString>']
    if run_context is not None:
        props.append(f'<token name="RunContext">{run_context}</token>')
        props.append('<bool name="Disabled">false</bool>')
    return f'<Item class="{cls}" referent="RBX{ref}"><Properties>{"".join(props)}</Properties></Item>'


# --------------------------------------------------------------------------- #
#  R6 riding pose as an Animation Editor KeyframeSequence (optional extra)
# --------------------------------------------------------------------------- #
import math


def keyframe_sequence():
    """Animation Editor version of the riding pose: the joint transforms RideKit's
    solver produced for surron1 (tests/ride_pose_transforms.json), looping
    idle -> cruise tuck -> idle."""
    import json
    with open(os.path.join(HERE, "tests", "ride_pose_transforms.json"), encoding="utf-8") as f:
        solved = {c["name"]: c for c in json.load(f)}
    part_of = {"Root": "Torso", "Neck": "Head", "RS": "Right Arm", "LS": "Left Arm", "RH": "Right Leg", "LH": "Left Leg"}
    ref = [100]

    def nref():
        ref[0] += 1
        return f"RBX{ref[0]}"

    def cf_xml(c):
        r = c["r"]
        vals = "".join(f"<R{i}{k}>{r[i * 3 + k]:.6f}</R{i}{k}>" for i in range(3) for k in range(3))
        return f'<CoordinateFrame name="CFrame"><X>0</X><Y>0</Y><Z>0</Z>{vals}</CoordinateFrame>'

    def pose(name, c, children=""):
        return (f'<Item class="Pose" referent="{nref()}"><Properties><string name="Name">{name}</string>'
                f'{cf_xml(c)}<float name="Weight">1</float>'
                f'<token name="EasingStyle">0</token><token name="EasingDirection">0</token>'
                f'</Properties>{children}</Item>')

    ident = {"r": [1, 0, 0, 0, 1, 0, 0, 0, 1]}
    frames = []
    for t, case in ((0.0, "idle"), (0.6, "cruise"), (1.2, "idle")):
        c = solved[case]
        limbs = "".join(pose(part_of[k], c[k]) for k in ("Neck", "RS", "LS", "RH", "LH"))
        torso = pose("Torso", c["Root"], limbs)
        root = pose("HumanoidRootPart", ident, torso)
        frames.append(f'<Item class="Keyframe" referent="{nref()}"><Properties><string name="Name">Keyframe</string>'
                      f'<float name="Time">{t}</float></Properties>{root}</Item>')
    return ('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
            'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
            'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">\n'
            '<Item class="KeyframeSequence" referent="RBX100"><Properties>'
            '<string name="Name">RidePose_R6</string><bool name="Loop">true</bool>'
            '<token name="Priority">2</token></Properties>\n' + "\n".join(frames) + "\n</Item>\n</roblox>\n")


def inline(name, fn):
    with open(os.path.join(SRC, fn), encoding="utf-8") as f:
        src = f.read().rstrip("\n")
    body = "\n".join(("\t" + l) if l.strip() else l for l in src.split("\n"))
    return f"local {name} = (function()\n{body}\nend)()\n"


def body_of(fn):
    with open(os.path.join(SRC, fn), encoding="utf-8") as f:
        src = f.read()
    b = src[src.index("-- @body"):]
    return b[:b.index("-- @end")] if "-- @end" in b else b


def single_files():
    """Copy-paste versions: one Script for the bike, one LocalScript for StarterPlayerScripts."""
    server = (
        "-- RideKit (server). PASTE INTO A *Script* DIRECTLY INSIDE THE BIKE MODEL\n"
        "-- (the Model that contains the two 'Wheel' parts).\n"
        "-- Also paste RideKit_Client.lua into a *LocalScript* in StarterPlayer > StarterPlayerScripts.\n\n"
        'local Players = game:GetService("Players")\n'
        'local RunService = game:GetService("RunService")\n\n'
        + inline("Config", "Config.lua") + inline("Rig", "Rig.lua") + inline("Physics", "Physics.lua")
        + "\nlocal bike = script.Parent :: Model\n\n" + body_of("BikeServer.server.lua"))
    client = (
        "-- RideKit (client). PASTE INTO A *LocalScript* IN StarterPlayer > StarterPlayerScripts.\n"
        "-- Drives, animates and poses (R6) every bike that has the RideKit server Script.\n\n"
        'local Players = game:GetService("Players")\n'
        'local RunService = game:GetService("RunService")\n'
        'local ContextActionService = game:GetService("ContextActionService")\n'
        'local CollectionService = game:GetService("CollectionService")\n\n'
        + inline("Config", "Config.lua") + inline("Physics", "Physics.lua") + inline("Pose", "Pose.lua")
        + "\n" + body_of("BikeClient.client.lua")
        + "\nfor _, b in ipairs(CollectionService:GetTagged(\"RideKitBike\")) do\n\ttask.spawn(runBike, b)\nend\n"
        "CollectionService:GetInstanceAddedSignal(\"RideKitBike\"):Connect(function(b)\n\ttask.spawn(runBike, b)\nend)\n")
    for name, text in (("RideKit_Server.lua", server), ("RideKit_Client.lua", client)):
        with open(os.path.join(HERE, name), "w", encoding="utf-8") as f:
            f.write(text)
        print("wrote", os.path.join(HERE, name))


def main():
    single_files()
    with open(os.path.join(HERE, "RidePose_R6.rbxmx"), "w", encoding="utf-8") as f:
        f.write(keyframe_sequence())
    parts = []
    for i, (cls, name, fn, rc) in enumerate(ITEMS, start=1):
        with open(os.path.join(SRC, fn), encoding="utf-8") as f:
            parts.append(item(cls, name, f.read(), i, rc))
    xml = ('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
           'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
           'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">\n'
           '<Item class="Folder" referent="RBX0"><Properties><string name="Name">RideKit</string></Properties>\n'
           + "\n".join(parts) + "\n</Item>\n</roblox>\n")
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(xml)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
