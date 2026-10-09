import {assert,assertEquals} from 'jsr:@std/assert@1';
import {medicalEvidencePolicy,recentGuidelineCatalog,supportedMedicalImageLink,
 vettedOpenverseImage,findOpenverseMedicalPreview} from './medical_evidence_media.ts';

const id='12345678-1234-4234-a234-123456789abc';
function image(props:Record<string,unknown>={}){
 return {id,title:'Normal sinus electrocardiogram ECG tracing',license:'by',
  creator:'Medical Illustrator',mature:false,...props};
}
Deno.test('current guideline policy mandates verified, current medical decisions',()=>{
 for(const word of ['RECOMMANDATIONS','récentes','sources','seuils','doses','surveillance',
  'ILLUSTRATIONS','Aucun stockage']){
  assert(medicalEvidencePolicy.toLowerCase().includes(word.toLowerCase()));
 }
});
Deno.test('only trusted HTTPS Openverse or Commons image/source pair allowed',()=>{
 const preview='https://api.openverse.org/v1/images/'+id+'/thumb/';
 const source='https://openverse.org/image/'+id;
 assert(supportedMedicalImageLink(preview,source));
 assert(supportedMedicalImageLink('https://upload.wikimedia.org/wikipedia/commons/file.png',
  'https://commons.wikimedia.org/wiki/File:Example.png'));
 assertEquals(supportedMedicalImageLink('https://evil.example/redirect',source),false);
 assertEquals(supportedMedicalImageLink(preview,'https://evil.example/page'),false);
 assertEquals(supportedMedicalImageLink(preview,'https://openverse.org/image/11111111-1111-4111-8111-111111111111'),false);
 assertEquals(supportedMedicalImageLink('http://api.openverse.org/v1/images/'+id+'/thumb/',source),false);
});
Deno.test('Openverse image metadata must be licensed, relevant and non-sensitive',()=>{
 const accepted=vettedOpenverseImage(image(),'normal ECG electrocardiogram');
 assert(accepted!==null);
 assertEquals(accepted.provider,'Openverse');
 assertEquals(accepted.preview_url,'https://api.openverse.org/v1/images/'+id+'/thumb/');
 assertEquals(accepted.source_url,'https://openverse.org/image/'+id);
 assertEquals(vettedOpenverseImage(image({license:'nc'}),'normal ECG'),null);
 assertEquals(vettedOpenverseImage(image({mature:true}),'normal ECG'),null);
 assertEquals(vettedOpenverseImage(image({title:'Sunset beach'}),'normal ECG'),null);
 assertEquals(vettedOpenverseImage(image(), 'normal ECG',/coronary/i),null);
 assertEquals(vettedOpenverseImage(image({id:'not-uuid'}),'normal ECG'),null);
});
Deno.test('provider outages do not block medical case or QCM creation',async()=>{
 // Empty input skips network, and a blank evidence catalog is handled conservatively.
 assertEquals(await findOpenverseMedicalPreview(''),null);
 assertEquals(await recentGuidelineCatalog(''), '');
});
