from pathlib import Path

path = Path('source/lib/screens/junior_oncall_screen.dart')
text = path.read_text(encoding='utf-8')
broken = """'Aucune garde ou astreinte Junior $day
à ${_juniorHospitalLabel(_activeHospital)}${_selectedService == _allServices ? '' : ' · $_selectedService'}.',"""
fixed = "'Aucune garde ou astreinte Junior $day\\nà ${_juniorHospitalLabel(_activeHospital)}${_selectedService == _allServices ? '' : ' · $_selectedService'}.',"
if broken in text:
    text = text.replace(broken, fixed, 1)
path.write_text(text, encoding='utf-8')
