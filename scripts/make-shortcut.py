#!/usr/bin/env python3
"""Generate a two-action capture workflow; sign it separately with Apple's shortcuts CLI."""
import argparse
import plistlib
import uuid
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--team', required=True, help='Team identifier matching the signed app')
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
assert len(args.team) == 10 and args.team.isalnum()
capture_id = str(uuid.uuid4()).upper()
workflow = {
    'WFWorkflowName': 'Capture to SnapLater',
    'WFWorkflowClientVersion': '1700',
    'WFWorkflowClientRelease': '26.0',
    'WFWorkflowMinimumClientVersion': 900,
    'WFWorkflowMinimumClientVersionString': '900',
    'WFWorkflowIcon': {'WFWorkflowIconStartColor': 4282601983, 'WFWorkflowIconGlyphNumber': 59511},
    'WFWorkflowInputContentItemClasses': [],
    'WFWorkflowTypes': ['MenuBar'],
    'WFWorkflowImportQuestions': [],
    'WFWorkflowHasShortcutInputVariables': False,
    'WFWorkflowActions': [
        {'WFWorkflowActionIdentifier': 'is.workflow.actions.takescreenshot',
         'WFWorkflowActionParameters': {'WFScreenshotType': 'Full Screen', 'UUID': capture_id}},
        {'WFWorkflowActionIdentifier': 'org.snaplater.local.SaveScreenshotIntent',
         'WFWorkflowActionParameters': {
             'AppIntentDescriptor': {'TeamIdentifier': args.team, 'BundleIdentifier': 'org.snaplater.local',
                                     'Name': 'SnapLater', 'AppIntentIdentifier': 'SaveScreenshotIntent'},
             'screenshot': {'Value': {'OutputUUID': capture_id, 'OutputName': 'Screenshot', 'Type': 'ActionOutput'},
                            'WFSerializationType': 'WFTextTokenAttachment'},
             'UUID': str(uuid.uuid4()).upper()}}
    ]
}
assert len(workflow['WFWorkflowActions']) == 2
assert workflow['WFWorkflowActions'][1]['WFWorkflowActionParameters']['screenshot']['Value']['OutputUUID'] == capture_id
assert not any(x['WFWorkflowActionIdentifier'] == 'is.workflow.actions.documentpicker.save' for x in workflow['WFWorkflowActions'])
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_bytes(plistlib.dumps(workflow, fmt=plistlib.FMT_BINARY))
assert plistlib.loads(args.output.read_bytes()) == workflow
print('Generated validated two-action workflow; no screenshot, API key, or personal content included.')
