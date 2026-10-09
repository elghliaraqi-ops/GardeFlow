import { allowedAsset, imageIsTopical, imageSearchTerms, legacyImageRequest,
  type ImagePreview } from './medical_image_previews.ts';

function assert(value: unknown, reason: string) {
  if (!value) throw new Error(reason);
}
const good:ImagePreview={
  thumbnail:'https://upload.wikimedia.org/wikipedia/commons/thumb/1/11/Rectum_anatomy.jpg',
  full:'https://upload.wikimedia.org/wikipedia/commons/1/11/Rectum_anatomy.jpg',
  source:'https://commons.wikimedia.org/wiki/File:Rectum_anatomy.jpg',
  title:'Rectum mesorectum sphincter labeled sagittal anatomy illustration',
  description:'Sagittal anatomy diagram of rectum and mesorectum',
  creator:'Open educational author',license:'CC BY-SA 4.0',provider:'Wikimedia Commons',
};

Deno.test('legacy rectal-anatomy description becomes strict anatomical diagram request',()=>{
  const r=legacyImageRequest({query:"Illustrer l'orientation anatomique du rectum, mésorectum et sphincters",modality:'schéma'});
  assert(r.image_type==='anatomical_diagram','must not select cancer MRI for normal anatomy');
  assert(imageSearchTerms(r).includes('anatomy'),'anatomical search must be used');
  assert(imageIsTopical(good,r),'sagittal mesorectal diagram should be eligible');
});

Deno.test('reject cover pages even if the title contains rectum, cancer, anatomy',()=>{
  const r=legacyImageRequest({query:"Anatomie du rectum et du mésorectum"});
  const cover={...good,title:'Rectum anatomy book cover - National Cancer Institute report',
    description:'medical book cover'};
  assert(!imageIsTopical(cover,r),'book covers must never appear as medical anatomy');
});

Deno.test('reject wrong organ, modality or image type',()=>{
  const r=legacyImageRequest({query:'Signal T2 du mésorectum et délimitation tumorale T3 vs T4',modality:'IRM T2'});
  assert(r.image_type==='radiology_scan','T2 request must be MRI');
  assert(!imageIsTopical(good,r),'normal anatomy diagram is not an MRI tumor');
  assert(!imageIsTopical({...good,title:'Prostate screening journal cover MRI',
    description:'MRI of prostate'},r),'prostate image must not appear in rectal MRI');
  assert(imageIsTopical({...good,title:'Rectal cancer T2 pelvic MRI extramural invasion',
    description:'Axial T2 MR image of rectal tumor'},r),'real T2 MRI metadata must be eligible');
});

Deno.test('image proxy refuses SSRF and does not allow arbitrary external hosts',()=>{
  assert(allowedAsset(good.thumbnail),'Wikimedia Commons original is allowed');
  assert(allowedAsset('https://live.staticflickr.com/75/20212345_a8b9c0d.jpg'),
    'Openverse/Flickr CC previews allowed');
  for(const bad of [
    'http://upload.wikimedia.org/a.png','https://evil.example/a.jpg',
    'https://127.0.0.1/test.jpg','https://upload.wikimedia.org.evil.com/img.png',
    'https://upload.wikimedia.org/../../secret.jpg',
    'https://upload.wikimedia.org/video.svg',
  ])assert(!allowedAsset(bad),'Must reject '+bad);
});
