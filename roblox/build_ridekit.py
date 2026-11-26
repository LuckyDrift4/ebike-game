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


def angles(x, y, z):
    """Roblox CFrame.Angles(x, y, z) = Rx * Ry * Rz, row-major 3x3."""
    cx, sx, cy, sy, cz, sz = math.cos(x), math.sin(x), math.cos(y), math.sin(y), math.cos(z), math.sin(z)
    rx = [[1, 0, 0], [0, cx, -sx], [0, sx, cx]]
    ry = [[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]
    rz = [[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]]
    mm = lambda a, b: [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
    return mm(mm(rx, ry), rz)


def cframe_xml(m):
    vals = "".join(f"<R{i}{j}>{m[i][j]:.6f}</R{i}{j}>" for i in range(3) for j in range(3))
    return f'<CoordinateFrame name="CFrame"><X>0</X><Y>0</Y><Z>0</Z>{vals}</CoordinateFrame>'


def pose_angles(lean, steer=0.0):
    """Same maths as RideKit/Pose.lua with throttle/speed at rest."""
    arm, leg = 1.05 - lean, 0.20 + lean
    return {
        "Torso": (lean, 0.0, -0.12 * steer),
        "Head": (-lean * 0.8, 0.0, 0.0),
        "Right Arm": (0.0, 0.0, arm - 0.22 * steer),
        "Left Arm": (0.0, 0.0, -(arm + 0.22 * steer)),
        "Right Leg": (-0.18, 0.0, leg),
        "Left Leg": (-0.18, 0.0, -leg),
    }


def keyframe_sequence():
    ref = [100]

    def nref():
        ref[0] += 1
        return f"RBX{ref[0]}"

    def pose(name, ang, children=""):
        return (f'<Item class="Pose" referent="{nref()}"><Properties><string name="Name">{name}</string>'
                f'{cframe_xml(angles(*ang))}<float name="Weight">1</float>'
                f'<token name="EasingStyle">0</token><token name="EasingDirection">0</token>'
                f'</Properties>{children}</Item>')

    frames = []
    for t, lean in ((0.0, 0.34), (0.6, 0.38), (1.2, 0.34)):  # gentle breathing / suspension bob loop
        a = pose_angles(lean)
        limbs = "".join(pose(n, a[n]) for n in ("Head", "Right Arm", "Left Arm", "Right Leg", "Left Leg"))
        torso = pose("Torso", a["Torso"], limbs)
        root = pose("HumanoidRootPart", (0, 0, 0), torso)
        frames.append(f'<Item class="Keyframe" referent="{nref()}"><Properties><string name="Name">Keyframe</string>'
                      f'<float name="Time">{t}</float></Properties>{root}</Item>')
    return ('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
            'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
            'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">\n'
            '<Item class="KeyframeSequence" referent="RBX100"><Properties>'
            '<string name="Name">RidePose_R6</string><bool name="Loop">true</bool>'
            '<token name="Priority">2</token></Properties>\n' + "\n".join(frames) + "\n</Item>\n</roblox>\n")


def main():
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
