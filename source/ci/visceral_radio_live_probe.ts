import {articleFigureSnippets, allowedAsset, probeMedicalFigure, resolveMedicalPreviews} from '../supabase/functions/generate-visceral-radio/medical_image_previews.ts';

const headers={'User-Agent':'GardeFlowPractice-Diagnostics/1.0 (public open-access media probe)','Accept':'application/xml, text/xml, image/jpeg, image/png, */*'};
async function request(url:string,method='GET'){
  try{
    const response=await fetch(url,{method,signal:AbortSignal.timeout(6500),
      redirect:'manual',headers});
    return {status:response.status,type:response.headers.get('content-type'),
      location:response.headers.get('location'),content:method==='GET'?await response.text():''};
  }catch(e){return {status:-1,type:null,location:null,content:String(e)};}
}
for(const pmcid of ['PMC7471246','PMC4463328']){
  const uri='https://www.ebi.ac.uk/europepmc/webservices/rest/'+pmcid+'/fullTextXML';
  const result=await request(uri);
  console.log('XML',pmcid,JSON.stringify({status:result.status,contentType:result.type,
    length:result.content.length,first:result.content.slice(0,100)}));
  const figures=articleFigureSnippets(result.content);
  console.log('FIGURES',pmcid,figures.length,figures.slice(0,4));
  const preferred=figures.filter(x=>/mri|t2|rect|anatom|sphinct|mesorect|tumou?r|axial/i.test(x.caption)).slice(0,2);
  for(const figure of preferred){
    const filename=figure.href.split('/').pop()||'';
    for(const ext of [filename,filename+'.jpg']){
      for(const host of ['https://europepmc.org','https://pmc.ncbi.nlm.nih.gov']){
        const url=host+'/articles/'+pmcid+'/bin/'+ext;
        if(!allowedAsset(url))continue;
        const head=await request(url,'HEAD');
        const valid=await probeMedicalFigure(url);
        console.log('MEDIA',JSON.stringify({pmcid,caption:figure.caption.slice(0,90),
          url,status:head.status,type:head.type,redirect:head.location,valid}));
      }
    }
  }
}
const input={query:'rectal cancer T2 MRI',purpose:'Signal T2 du mésorectum et délimitation tumorale T3 vs T4',
  anatomy:'rectum',modality:'IRM T2',image_type:'radiology_scan',plane:'axial',
  required_features:['rectal tumor'],excluded_features:[],fallback_queries:[]};
const result=await resolveMedicalPreviews(input);
console.log('RESOLVE',JSON.stringify({images:result.images?.length,articles:result.article_previews?.length,
  articlesWithImage:result.article_previews?.filter((x:any)=>Boolean(x.thumbnail)).length,
  imageOrigins:result.images?.map((x:any)=>x.thumbnail),articleTitles:result.article_previews?.map((x:any)=>x.title),
  reason:result.unavailable_reason}));
