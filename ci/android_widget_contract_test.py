#!/usr/bin/env python3
from pathlib import Path
from xml.etree import ElementTree as ET
import re
root=Path(__file__).resolve().parents[1]
r=root/"source/tool/android-res"
layout=ET.parse(r/"layout/gardeflow_widget.xml").getroot()
attr="{http://schemas.android.com/apk/res/android}"
ids={x.attrib[attr+"id"].split("/")[-1] for x in layout.iter() if attr+"id" in x.attrib}
kt=(root/"source/tool/android-src/GardeFlowWidgetProvider.kt").read_text()
dart=(root/"source/lib/services/android_widget_service.dart").read_text()
for id_ in re.findall(r"R\.id\.(widget_[A-Za-z0-9_]+)",kt):
    assert id_ in ids, f"Widget missing: {id_}"
for view in layout.iter():
    for key in ("background","progressDrawable"):
        name=view.attrib.get(attr+key,"")
        if name.startswith("@drawable/"):
            assert (r/"drawable"/(name.split("/")[-1]+".xml")).exists(),name
for key in ("planning_line_1","astreintes_subdetail","practice_subdetail",
            "practice_answered","practice_progress","sync_label"):
    assert f"'{key}':" in dart
    assert f'"{key}"' in kt
assert "setProgressBar(R.id.widget_practice_progress, 100, accuracy, false)" in kt
print("PASS: GardeFlow native widget resources & data bindings")

# Live guard status and current date are handled in the native provider.
assert "widget_next_eyebrow" in ids
assert "GARDE EN COURS" in kt
assert "SimpleDateFormat" in kt
assert 'if (visual.periodLabel.isBlank())' in kt
