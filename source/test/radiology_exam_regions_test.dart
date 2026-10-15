import 'package:flutter_test/flutter_test.dart';
import 'package:huim6_planning/data/radiology_exam_regions.dart';

void main() {
  test('each modality has distinct imaging regions and a custom option', () {
    for (final exam in RadiologyExamRegions.exams) {
      final list = RadiologyExamRegions.forExam(exam);
      expect(list, isNotEmpty, reason: exam);
      expect(list.last, RadiologyExamRegions.customRegion);
      expect(list.length, greaterThan(8), reason: exam);
      expect(list.toSet().length, list.length, reason: exam);
    }
    expect(RadiologyExamRegions.forExam('TDM'),
      contains('Thoraco-abdomino-pelvien (TAP)'));
    expect(RadiologyExamRegions.forExam('TDM'),
      contains('Abdomino-pelvien'));
    expect(RadiologyExamRegions.forExam('TDM'),
      contains('Sinus de la face'));
    expect(RadiologyExamRegions.forExam('TDM'),
      contains('Rochers'));
    expect(RadiologyExamRegions.forExam('IRM'),
      contains('Hypophyse / selle turcique'));
    expect(RadiologyExamRegions.forExam('Échographie'),
      contains('Pelvis / gynécologique'));
    expect(RadiologyExamRegions.forExam('Radiographie'),
      contains('Thorax'));
    expect(RadiologyExamRegions.forExam('Doppler'),
      contains('Veines des membres inférieurs'));
    expect(RadiologyExamRegions.forExam('Angio-TDM'),
      contains('Artères pulmonaires / embolie pulmonaire'));
    expect(RadiologyExamRegions.forExam('Angio-IRM'),
      contains('Artères cérébrales / polygone de Willis'));
  });

  test('changing the exam actually changes proposed anatomy', () {
    final ct = RadiologyExamRegions.forExam('TDM');
    final doppler = RadiologyExamRegions.forExam('Doppler');
    expect(ct, isNot(contains('Veines des membres inférieurs')));
    expect(doppler, isNot(contains('Thoraco-abdomino-pelvien (TAP)')));
    expect(RadiologyExamRegions.forExam('Unlisted'),
      contains(RadiologyExamRegions.customRegion));
  });
}
