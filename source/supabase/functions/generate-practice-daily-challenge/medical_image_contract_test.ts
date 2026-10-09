import {medicalImageSchema,medicalImagePrompt,
 emptyMedicalImageRequest,medicalImageCorrectionSuffix}
 from './medical_image_contract.ts';

Deno.test('Groq prompt and JSON image contract share all 8 required fields',()=>{
 const keys=Object.keys(medicalImageSchema.properties);
 if(keys.length!==8||medicalImageSchema.required.join('|')!==keys.join('|'))
  throw Error('image_fields_mismatch');
 for(const name of keys)if(!medicalImagePrompt.includes(name))
  throw Error('prompt_missing_'+name);
 if(medicalImageSchema.additionalProperties!==false)
  throw Error('unspecified URLs are forbidden');
});
Deno.test('no image produces no metadata, never invents a link',()=>{
 if(medicalImageCorrectionSuffix(emptyMedicalImageRequest)!=='')
  throw Error('irrelevant_image_must_be_empty');
});
Deno.test('matching radiology image request is serialized for dynamic lookup',()=>{
 const suffix=medicalImageCorrectionSuffix({
  query:'rectal cancer T2 pelvic MRI',image_type:'radiology_scan',
  anatomy:'rectum',modality:'IRM T2',plane:'axial',
  purpose:'T2 tumor invasion',required_features:['tumor','mesorectum'],
  excluded_features:['book cover']});
 if(!suffix.includes('§IMAGE_SPEC§'))throw Error('no_image_json');
 const obj=JSON.parse(suffix.split('§IMAGE_SPEC§')[1]);
 if(obj.image_type!=='radiology_scan'||obj.required_features[0]!=='tumor')
  throw Error('image_json_not_preserved');
 if(obj.full||obj.thumbnail||obj.image_url)throw Error('remote_url_stored');
});
