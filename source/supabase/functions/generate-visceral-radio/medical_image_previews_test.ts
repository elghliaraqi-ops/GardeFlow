import {medicalSearchTerms} from './medical_image_previews.ts';
function check(ok:boolean,why:string){if(!ok)throw new Error(why);}
Deno.test('historic French rectal anatomy searches resolve into MRI terms',()=>{
  const q=medicalSearchTerms("Illustrer l'orientation anatomique du rectum, mésorectum et sphincters",'IRM');
  check(q.includes('rectum'),'rectum should be central');
  check(q.includes('MRI'),'MRI modality should be present');
});
Deno.test('surgical radiology search retains clinical topic',()=>{
  check(medicalSearchTerms('TDM appendicite aiguë').includes('appendicitis'),'appendicitis');
  check(medicalSearchTerms('Pancréatite aiguë TDM').includes('pancreatitis'),'pancreatitis');
  check(medicalSearchTerms('Cholécystite aiguë échographie').includes('cholecystitis'),'cholecystitis');
});
Deno.test('empty image requests still have safe fallback terms',()=>{
  check(medicalSearchTerms('Illustrer la coupe').length>0,'empty search fallback');
});
