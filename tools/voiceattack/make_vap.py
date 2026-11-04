#!/usr/bin/env python3
# make_vap | v1.0.0
"""
VoiceAttack command set for the TRT F10 menu (Menu_Manager >= v1.2.0, hook TRT_VoiceBridge).

Writes TRT_F10_Voice.vap: a profile file meant for VoiceAttack "Import Commands" into the
profile Pathe_01 (not for "Import Profile"). Every command only sets two text variables and
runs "((TRT voice send))", whose inline C# sends one UDP datagram to the DCS hook. No key
presses: the hook resolves the call by its F10 label, so F-key positions do not matter.

Composite (prefix + suffix, group "TRT") for calls that open with the station called:
    "Overlord, Hornet five one," + "request picture"
Full commands for brevity calls said without the station's call sign (JTAC attack calls,
ball call, utility).

Usage:  python tools/voiceattack/make_vap.py            -> writes the .vap + tests json
"""
import json
import uuid
from pathlib import Path
from xml.sax.saxutils import escape

HERE = Path(__file__).resolve().parent
OUT_VAP = HERE / "TRT_F10_Voice.vap"
OUT_TEST = HERE / "voice_keys_test.json"

CATEGORY = "TRT F10"
GROUP = "TRT"
UDP_PORT = 47011
HELPER = "((TRT voice send))"

NS = uuid.UUID("6f1c2a52-7d0e-4c1b-9a7e-5d3b0c7a1e01")      # stable ids across rebuilds
def gid(*parts):
    return str(uuid.uuid5(NS, "|".join(parts)))

# ── call signs ────────────────────────────────────────────────────────────────
OWN = "[Hornet five one;]"                       # CAS-1 call sign
SIDE = "[four six seven;Hornet five one;]"       # carrier nets: modex (CV_Comms fallback 467) or call sign
JTACS = [("Pointer", "pointer 11"), ("Eyeball", "eyeball 11"),
         ("Axeman", "axeman 11"), ("Darknight;Dark Knight", "darknight 11")]
JT_OPT = "[Pointer one one;Eyeball one one;Axeman one one;Darknight one one;Dark Knight one one;]"
DIRS = "north;northeast;east;southeast;south;southwest;west;northwest"
FIELDS = "Incirlik;Injirlik;Akrotiri"

# ── PREFIXES: station called (+ own call sign) -> TRT.ag ──────────────────────
PREFIXES = [
    ("Overlord " + OWN,                         "overlord"),
    ("Strike " + SIDE,                          "strike"),
    ("Texaco [one one;] " + OWN,                "texaco"),
    ("Marshal " + SIDE,                         "marshal"),
    ("[%s;] Approach %s" % (FIELDS, SIDE),      "approach"),     # CV approach and divert-field approach
    ("Departure " + SIDE,                       "departure"),
    ("Paddles " + SIDE,                         "paddles"),
    ("Ankara [Control;] " + OWN,                "ankara"),
    ("[%s;] Tower %s" % (FIELDS, OWN),          "tower"),
    ("[%s;] Ground %s" % (FIELDS, OWN),         "ground"),
] + [("[%s] one one %s" % (sp, OWN), ag) for sp, ag in JTACS]

# ── SUFFIXES: the call, key with @ag (replaced by TRT.ag; "*" if unset) ───────
# (phrase, key, [(agency, expected label), ...] for the self-test)
SUFFIXES = [
    ("checking in [as fragged;outbound;]", "@ag: check in | @ag: rv initial",
        [("overlord", "OVERLORD: check in (btn 3)"), ("strike", "STRIKE: check in (btn 6)"),
         ("marshal", "MARSHAL: check in 264.00 (#16)"), ("approach", "APPROACH: check in 271.00 (#15)"),
         ("pointer 11", "POINTER 11: check in (btn 4)"), ("ankara", "ANKARA: check in (357.5)"),
         ("tower", "TOWER: check in (360.1)"), ("texaco", "TEXACO: RV initial (btn 7)")]),
    ("inbound;checking in inbound", "@ag: check in inbound",
        [("strike", "STRIKE: check in inbound (btn 6)")]),
    ("request taxi", "@ag: request taxi", [("ground", "GROUND: request taxi (250.0)")]),
    ("request picture;picture", "@ag: request picture", [("overlord", "OVERLORD: request picture")]),
    ("feet dry", "@ag: feet dry", [("overlord", "OVERLORD: feet dry")]),
    ("feet wet", "@ag: feet wet", [("overlord", "OVERLORD: feet wet")]),
    ("in flight rep;in flight report;ready to pass in flight rep", "@ag: infltrep",
        [("overlord", "OVERLORD: INFLTREP")]),
    ("wilco [divert;]", "@ag: wilco divert", [("overlord", "OVERLORD: wilco divert (Eyeball 11)")]),
    ("unable [divert;]", "@ag: unable divert", [("overlord", "OVERLORD: unable divert, state 6.2")]),
    ("continuing mission [without tanker;no tanker;]", "@ag: continuing mission",
        [("overlord", "OVERLORD: continuing mission, no tanker")]),
    ("RTB;off Texaco RTB;no tanker required RTB", "@ag: rtb= | @ag: rtb (no tanker)",
        [("overlord", "OVERLORD: RTB")]),
    ("mission abort [RTB;];abort mission [RTB;]", "@ag: rtb (mission abort)",
        [("overlord", "OVERLORD: RTB (mission abort)")]),
    ("request Texaco;request tanker", "@ag: request texaco",
        [("overlord", "OVERLORD: request Texaco (AR1 top-off)")]),
    ("negative Texaco;no top off", "@ag: skip ar1", [("overlord", "OVERLORD: skip AR1 (no top-off)")]),
    ("off Texaco [proceeding [C P;] Tiger;]", "@ag: off texaco",
        [("overlord", "OVERLORD: off Texaco, proceeding TIGER")]),
    ("bingo [fuel;] [diverting;] [nearest field;%s;]" % FIELDS, "@ag: bingo",
        [("overlord", "OVERLORD: bingo / divert (nearest field)")]),
    ("execute overrun", "@ag: execute overrun", [("texaco", "TEXACO: execute overrun")]),
    ("breakaway [breakaway;] [breakaway;]", "@ag: breakaway", [("texaco", "TEXACO: breakaway (emergency)")]),
    ("state", "@ag: state", [("texaco", "TEXACO: state")]),
    ("readback", "@ag: 9-line readback | @ag: readback",
        [("marshal", "MARSHAL: readback"), ("pointer 11", "POINTER 11: 9-line readback (4/6/8)")]),
    ("established [angels [1..30];]", "@ag: established", [("marshal", "MARSHAL: established")]),
    ("commencing", "@ag: commencing", [("marshal", "MARSHAL: commencing (EAT :25, T-1:30)")]),
    ("see you at ten", "@ag: see you at 10",
        [("marshal", "MARSHAL: see you at 10"), ("approach", "APPROACH: see you at 10")]),
    ("platform", "@ag: platform", [("approach", "APPROACH: platform")]),
    ("needles up and on;up and on", "@ag: needles up and on", [("approach", "APPROACH: needles up and on")]),
    ("negative needles;needles negative", "@ag: needles negative", [("approach", "APPROACH: needles negative")]),
    ("Popeye [angels [1..30];]", "@ag: popeye", [("departure", "DEPARTURE: Popeye, angels 5")]),
    ("on top [angels [1..30];]", "@ag: on top", [("departure", "DEPARTURE: on top, angels 7")]),
    ("tanking complete", "@ag: tanking complete",
        [("departure", "DEPARTURE: tanking complete (state) 251.00 (#2)")]),
    ("how copy", "@ag: how copy", [("pointer 11", "POINTER 11: how copy? (no answer)")]),
] + [("off %s one one [mission complete;] [ready for retasking;]" % sp, "@ag: off " + ag,
        [("overlord", "OVERLORD: off %s, ready for retasking" % ag.title())]) for sp, ag in JTACS] \
  + [("unable contact %s one one" % sp, "@ag: unable contact " + ag,
        [("overlord", "OVERLORD: unable contact %s" % ag.title())]) for sp, ag in JTACS]

# ── FULL commands: (phrase, section, key, expected label path for the self-test) ─
JT = JT_OPT + " " + OWN
FULL = [
    # JTAC dialogue / attack brevity (JP 3-09.3), station call sign optional
    (JT + " ready for game plan", "COMMS", "*: ready for game plan", "POINTER 11: ready for game plan"),
    (JT + " ready for nine line", "COMMS", "*: ready for 9-line", "POINTER 11: ready for 9-line"),
    (JT + " ready for remarks", "COMMS", "*: ready for remarks", "POINTER 11: ready for remarks"),
    (JT + " IP inbound", "COMMS", "*: ip inbound", "POINTER 11: IP INBOUND"),
    (JT_OPT + " Hornet five one in [from the %s;]" % DIRS.replace(";", ";from the "), "COMMS",
        "*: in (", "POINTER 11: IN (direction auto)"),
    (JT_OPT + " Hornet five one off [%s;]" % DIRS, "COMMS", "*: off= | *: off (dry)", "POINTER 11: OFF"),
    (JT + " ten seconds", "COMMS", "*: ten seconds", "POINTER 11: TEN SECONDS"),
    (JT + " laser on", "COMMS", "*: laser on", "POINTER 11: LASER ON"),
    (JT + " spot", "COMMS", "*: spot=", "POINTER 11: SPOT"),
    (JT + " negative laser", "COMMS", "*: negative laser", "POINTER 11: NEGATIVE LASER"),
    (JT + " shift [laser;]", "COMMS", "*: shift", "POINTER 11: SHIFT (laser to next target)"),
    (JT + " cease laser;" + JT + " terminate [laser;]", "COMMS", "*: cease laser", "POINTER 11: CEASE LASER"),
    (JT + " tally [target;]", "COMMS", "*: correlation > tally=", "POINTER 11: correlation > TALLY"),
    (JT + " captured", "COMMS", "*: correlation > captured=", "POINTER 11: correlation > CAPTURED"),
    (JT + " no joy", "COMMS", "*: correlation > no joy=", "POINTER 11: correlation > NO JOY"),
    (JT + " aborting [aborting;] [aborting;]", "COMMS", "*: aborting", "POINTER 11: ABORTING"),
    (JT + " authenticate", "COMMS", "*: authenticate", "POINTER 11: AUTHENTICATE"),
    (JT + " Winchester", "COMMS", "*: winchester", "POINTER 11: WINCHESTER (check out)"),
    ("[readback;] option one", "COMMS", "*: readback > #1", "POINTER 11: READBACK 1/3: Line 4 > #1"),
    ("[readback;] option two", "COMMS", "*: readback > #2", "POINTER 11: READBACK 1/3: Line 4 > #2"),
    ("[readback;] option three", "COMMS", "*: readback > #3", "POINTER 11: READBACK 1/3: Line 4 > #3"),
    ("[readback;] option four", "COMMS", "*: readback > #4", "POINTER 11: READBACK 1/3: Line 4 > #4"),
    # carrier / tanker calls made without the station's call sign
    ("[four six seven;] Hornet ball [state;]", "COMMS", "paddles: ball", "PADDLES: ball (Hornet ball, state)"),
    ("[four six seven;] Clara [ship;]", "COMMS", "paddles: clara", "PADDLES: Clara"),
    ("[Overlord;] " + OWN + " Judy", "COMMS", "overlord: judy", "OVERLORD: Judy (tanker visual)"),
    ("breakaway breakaway [breakaway;]", "COMMS", "texaco: breakaway", "TEXACO: breakaway (emergency)"),
    (OWN + " spokes", "COMMS", "texaco: spokes", "TEXACO: spokes (drogue damaged)"),
    # AIRBOSS requests (F10 > CARRIER, RECOVERY phase)
    ("[Marshal;Paddles;] [four six seven;] spinning", "CARRIER", "spinning", "Spinning"),
    ("[Marshal;] [four six seven;] declaring emergency;request emergency landing", "CARRIER",
        "emergency landing", "Emergency landing"),
    # plane captain (F10 > CARRIER > Plane captain, deck)
    ("ready to start;ready for start", "CARRIER", "plane captain > ready to start", "Plane captain > Ready to start"),
    ("ready for checks", "CARRIER", "plane captain > ready for checks",
        "Plane captain > Ready for checks (engines running)"),
    ("step complete;check complete", "CARRIER", "plane captain > done", "Plane captain > Done (pilot signal)"),
    ("skip step;skip this step", "CARRIER", "plane captain > skip step", "Plane captain > Skip step"),
    ("abort checks", "CARRIER", "plane captain > abort checks", "Plane captain > Abort checks"),
    # screen information (not radio calls)
    ("next call;say next call;what's next", "COMMS", "show: next call", "Show: next call"),
    ("[show;] comm card", "INFO", "show: comm card", "Show: comm card"),
    ("[show;] hard deck", "INFO", "show: hard deck", "Show: hard deck"),
    ("[show;] flight card", "INFO", "show: flight card", "Show: flight card"),
    ("[show;] timeline", "INFO", "show: timeline", "Show: timeline"),
    ("[show;] ELINT picture", "INFO", "show: elint picture", "Show: ELINT picture"),
    ("[show;] divert summary", "INFO", "show: divert summary", "Show: divert summary"),
    ("end sortie;show flight report", "INFO", "flight report: end sortie", "FLIGHT REPORT: end sortie (show report)"),
    ("[show;] score detail", "INFO", "flight report: score detail", "FLIGHT REPORT: score detail"),
    ("[show;] text report", "INFO", "flight report: text report", "FLIGHT REPORT: text report"),
    ("[show;] carrier info", "CARRIER", "carrier info", "Carrier info"),
    ("carrier weather;[show;] weather report", "CARRIER", "weather report", "Weather report"),
    ("[show;] my status", "CARRIER", "my status", "My status"),
    ("[show;] attitude monitor", "CARRIER", "attitude monitor", "Attitude monitor"),
    ("[show;] greenie board", "CARRIER", "results > greenie board", "Results > Greenie board"),
    ("[show;] my grades;[show;] my LSO grades", "CARRIER", "results > my lso grades", "Results > My LSO grades"),
    ("[show;] last debrief", "CARRIER", "results > last debrief", "Results > Last debrief"),
]

# ── C# helper ─────────────────────────────────────────────────────────────────
CS = r'''using System;
using System.Net.Sockets;
using System.Text;

// TRT voice send | v1.0.0  (make_vap.py) - one UDP datagram to the DCS hook TRT_VoiceBridge
public class VAInline
{
    public void main()
    {
        string key = VA.GetText("TRT.vKey");
        if (string.IsNullOrEmpty(key)) return;
        string sec = VA.GetText("TRT.vSec");
        if (string.IsNullOrEmpty(sec)) sec = "COMMS";
        string ag = VA.GetText("TRT.ag");
        if (string.IsNullOrEmpty(ag)) ag = "*";
        key = key.Replace("@ag", ag);
        string said = VA.ParseTokens("{LASTSPOKENCMD}");
        if (said == null) said = "";
        string msg = "TRTV1\t" + sec + "\t" + key + "\t" + said.Replace("\t", " ");
        byte[] b = Encoding.UTF8.GetBytes(msg);
        try
        {
            using (UdpClient u = new UdpClient())
            {
                u.Send(b, b.Length, "127.0.0.1", PORT);
            }
            VA.WriteToLog("TRT voice: " + sec + " | " + key, "blue");
        }
        catch (Exception e)
        {
            VA.WriteToLog("TRT voice: send failed - " + e.Message, "red");
        }
        VA.SetText("TRT.vKey", null);
        VA.SetText("TRT.vSec", null);
        VA.SetText("TRT.ag", null);
    }
}
'''.replace("PORT", str(UDP_PORT))
REFS = "Microsoft.CSharp.dll;System.dll;System.Core.dll"

# ── XML ───────────────────────────────────────────────────────────────────────
def action(aid, atype, context="", context2=None, context3=None, x=0):
    c2 = "<Context2 />" if context2 is None else '<Context2 xml:space="preserve">%s</Context2>' % escape(context2)
    c3 = "<Context3 />" if context3 is None else "<Context3>%s</Context3>" % escape(context3)
    return f"""        <CommandAction>
          <PairingSet>false</PairingSet>
          <PairingSetElse>false</PairingSetElse>
          <Ordinal>0</Ordinal>
          <ConditionMet xsi:nil="true" />
          <IndentLevel>0</IndentLevel>
          <ConditionSkip>false</ConditionSkip>
          <IsSuffixAction>false</IsSuffixAction>
          <DecimalTransient1>0</DecimalTransient1>
          <Id>{aid}</Id>
          <ActionType>{atype}</ActionType>
          <Duration>0</Duration>
          <Delay>0</Delay>
          <KeyCodes />
          <Context xml:space="preserve">{escape(context)}</Context>
          {c2}
          {c3}
          <Context4 />
          <X>{x}</X>
          <Y>0</Y>
          <Z>0</Z>
          <InputMode>0</InputMode>
          <ConditionPairing>0</ConditionPairing>
          <ConditionGroup>0</ConditionGroup>
          <ConditionStartOperator>0</ConditionStartOperator>
          <ConditionStartValue>0</ConditionStartValue>
          <ConditionStartValueType>0</ConditionStartValueType>
          <ConditionStartType>0</ConditionStartType>
          <DecimalContext1>0</DecimalContext1>
          <DecimalContext2>0</DecimalContext2>
          <DateContext1>0001-01-01T00:00:00</DateContext1>
          <DateContext2>0001-01-01T00:00:00</DateContext2>
          <Disabled>false</Disabled>
          <RandomSounds />
          <ConditionExpressions />
          <IntegerContext1>{2 if atype == 'InlineFunctionCS' else 0}</IntegerContext1>
          <IntegerContext2>0</IntegerContext2>
        </CommandAction>
"""

def text_set(cid, n, var, val):
    return action(gid(cid, "a", str(n)), "TextSet", var, val)

def command(cid, phrase, actions, ctype=0, spoken=True, desc=""):
    group = f"\n      <CompositeGroup>{GROUP}</CompositeGroup>" if ctype in (1, 2) else ""
    return f"""    <Command>
      <Referrer xsi:nil="true" />
      <ExecType>3</ExecType>
      <Confidence>0</Confidence>
      <PrefixActionCount>0</PrefixActionCount>
      <IsDynamicallyCreated>false</IsDynamicallyCreated>
      <TargetProcessSet>false</TargetProcessSet>
      <TargetProcessType>0</TargetProcessType>
      <TargetProcessLevel>0</TargetProcessLevel>
      <CompareType>0</CompareType>
      <ExecFromWildcard>false</ExecFromWildcard>
      <IsSubCommand>false</IsSubCommand>
      <IsOverride>false</IsOverride>
      <BaseId>{gid(cid, 'base')}</BaseId>
      <OriginId>00000000-0000-0000-0000-000000000000</OriginId>
      <SessionEnabled>true</SessionEnabled>
      <DoubleTapInvoked>false</DoubleTapInvoked>
      <SingleTapDelayedInvoked>false</SingleTapDelayedInvoked>
      <LongTapInvoked>false</LongTapInvoked>
      <ShortTapDelayedInvoked>false</ShortTapDelayedInvoked>
      <SleepFlag>0</SleepFlag>
      <Id>{gid(cid)}</Id>
      <CommandString>{escape(phrase)}</CommandString>
      <ActionSequence>
{''.join(actions)}      </ActionSequence>
      <Async>true</Async>
      <Enabled>true</Enabled>
      <Category>{CATEGORY}</Category>
      <UseShortcut>false</UseShortcut>
      <keyValue>0</keyValue>
      <keyShift>0</keyShift>
      <keyAlt>0</keyAlt>
      <keyCtrl>0</keyCtrl>
      <keyWin>0</keyWin>
      <keyPassthru>true</keyPassthru>
      <UseSpokenPhrase>{'true' if spoken else 'false'}</UseSpokenPhrase>
      <onlyKeyUp>false</onlyKeyUp>
      <RepeatNumber>2</RepeatNumber>
      <RepeatType>0</RepeatType>
      <CommandType>{ctype}</CommandType>{group}
      <SourceProfile>00000000-0000-0000-0000-000000000000</SourceProfile>
      <UseConfidence>false</UseConfidence>
      <minimumConfidenceLevel>0</minimumConfidenceLevel>
      <UseJoystick>false</UseJoystick>
      <joystickNumber>0</joystickNumber>
      <joystickButton>0</joystickButton>
      <joystickNumber2>0</joystickNumber2>
      <joystickButton2>0</joystickButton2>
      <joystickUp>false</joystickUp>
      <KeepRepeating>false</KeepRepeating>
      <UseProcessOverride>false</UseProcessOverride>
      <ProcessOverrideActiveWindow>true</ProcessOverrideActiveWindow>
      <LostFocusStop>false</LostFocusStop>
      <PauseLostFocus>false</PauseLostFocus>
      <LostFocusBackCompat>true</LostFocusBackCompat>
      <UseMouse>false</UseMouse>
      <MouseUpOnly>false</MouseUpOnly>
      <MousePassThru>true</MousePassThru>
      <joystickExclusive>false</joystickExclusive>
      <UseProfileProcessOverride>false</UseProfileProcessOverride>
      <ProfileProcessOverrideActiveWindow>false</ProfileProcessOverrideActiveWindow>
      <RepeatIfKeysDown>false</RepeatIfKeysDown>
      <RepeatIfMouseDown>false</RepeatIfMouseDown>
      <RepeatIfJoystickDown>false</RepeatIfJoystickDown>
      <AH>0</AH>
      <CL>0</CL>
      <HasMB>false</HasMB>
      <UseVariableHotkey>false</UseVariableHotkey>
      <CLE>0</CLE>
      <EX1>false</EX1>
      <EX2>false</EX2>
      <InternalId xsi:nil="true" />
      <HasInput>false</HasInput>
      <AlwaysExec>false</AlwaysExec>
      <ResourceBalance>0</ResourceBalance>
      <PreventExec>false</PreventExec>
      <ExternalEventsEnabled>false</ExternalEventsEnabled>
      <ExcludeExecOnRecognized>false</ExcludeExecOnRecognized>
      <UseVariableMouseShortcut>false</UseVariableMouseShortcut>
      <UseVariableJoystickShortcut>false</UseVariableJoystickShortcut>
      <Description>{escape(desc)}</Description>
    </Command>
"""

def build():
    cmds, tests = [], {"suffix": [], "full": []}
    helper_id = gid("helper")
    # helper (not spoken)
    cmds.append(command("helper", HELPER,
        [action(gid("helper", "a", "0"), "InlineFunctionCS", CS, REFS, "TRT voice send", x=1)],
        spoken=False, desc="Sends TRT.vSec / TRT.vKey (+ TRT.ag) to the DCS hook TRT_VoiceBridge, UDP 127.0.0.1:%d"
        % UDP_PORT).replace(f"<Id>{gid('helper')}</Id>", f"<Id>{helper_id}</Id>"))

    def run_helper(cid):
        return action(gid(cid, "a", "x"), "ExecuteCommand", helper_id, x=1)

    for i, (phrase, ag) in enumerate(PREFIXES):
        cid = "prefix|" + ag + "|" + str(i)
        cmds.append(command(cid, phrase, [text_set(cid, 0, "TRT.ag", ag)], ctype=1,
                            desc="TRT station prefix -> " + ag))
    for phrase, key, exp in SUFFIXES:
        cid = "suffix|" + key
        cmds.append(command(cid, phrase, [text_set(cid, 0, "TRT.vSec", "COMMS"),
                                          text_set(cid, 1, "TRT.vKey", key), run_helper(cid)],
                            ctype=2, desc="COMMS | " + key))
        tests["suffix"].append({"phrase": phrase, "key": key, "expect": exp})
    for phrase, sec, key, exp in FULL:
        cid = "full|" + sec + "|" + key
        cmds.append(command(cid, phrase, [text_set(cid, 0, "TRT.vSec", sec),
                                          text_set(cid, 1, "TRT.vKey", key), run_helper(cid)],
                            desc=sec + " | " + key))
        tests["full"].append({"phrase": phrase, "section": sec, "key": key, "expect": exp})

    xml = f"""<?xml version="1.0" encoding="utf-8"?>
<Profile xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
  <HasMB>false</HasMB>
  <Id>{gid('profile')}</Id>
  <Name>TRT F10 Voice (import into Pathe_01)</Name>
  <Commands>
{''.join(cmds)}  </Commands>
  <OverrideGlobal>false</OverrideGlobal>
  <GlobalHotkeyIndex>0</GlobalHotkeyIndex>
  <GlobalHotkeyEnabled>false</GlobalHotkeyEnabled>
  <GlobalHotkeyValue>0</GlobalHotkeyValue>
  <GlobalHotkeyShift>0</GlobalHotkeyShift>
  <GlobalHotkeyAlt>0</GlobalHotkeyAlt>
  <GlobalHotkeyCtrl>0</GlobalHotkeyCtrl>
  <GlobalHotkeyWin>0</GlobalHotkeyWin>
  <GlobalHotkeyPassThru>false</GlobalHotkeyPassThru>
  <ExcludeGlobalProfiles>false</ExcludeGlobalProfiles>
  <Deleted>false</Deleted>
</Profile>
"""
    OUT_VAP.write_text(xml, encoding="utf-8")
    OUT_TEST.write_text(json.dumps(tests, indent=1), encoding="utf-8")
    n = len(cmds)
    print(f"{OUT_VAP.name}: {n} commands ({len(PREFIXES)} prefix, {len(SUFFIXES)} suffix, "
          f"{len(FULL)} full, 1 helper)")

if __name__ == "__main__":
    build()
