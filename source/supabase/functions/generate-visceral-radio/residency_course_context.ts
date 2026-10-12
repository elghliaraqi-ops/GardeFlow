// Use taught material, not chapter names, without sending the whole long course.
export function courseContext(fiche: any, maxChars = 3500, offset?:number): string {
  const all=Array.isArray(fiche?.sections) ? fiche.sections : [];
  const indices=offset===undefined?all.map((_:any,i:number)=>i):offset<10?[0,1,2,3,4,5]:[1,5,6,7,8,9];
  const sections = indices.map((i:number)=>all[i]).filter(Boolean).map((s:any) => ({
    key:String(s.key??''), title:String(s.title??''),
    key_points:(Array.isArray(s.key_points)?s.key_points:[]).map((p:any)=>String(p)),
  }));
  let context={title:String(fiche?.title??''),sections};
  while(JSON.stringify(context).length>maxChars && context.sections.some((s:any)=>s.key_points.length>1)) {
    context={...context,sections:context.sections.map((s:any)=>({...s,key_points:s.key_points.slice(0,Math.max(1,s.key_points.length-1))}))};
  }
  if(JSON.stringify(context).length>maxChars) throw new Error('course_context_too_large');
  return JSON.stringify(context);
}

export function courseTeachingPolicy(): string {
  return 'NIVEAU RÉSIDANAT : enseigne les critères discriminants, leur justification, les rapports anatomiques utiles, les classifications applicables, les indications/contre-indications et les alternatives selon stabilité et terrain, les étapes opératoires, la surveillance et les pièges. '+
    'Une correction explique le raisonnement, pas seulement la lettre correcte. Les notions évaluées doivent être expliquées dans le support transmis. '+
    'Ne réduis pas le niveau des QCM pour compenser un cours superficiel. Pour un ancien support, enrichis le cours à partir des notions déjà évaluées sans modifier réponses, scores ou faits du patient. '+
    'Si une information fiable manque, explique la limite ; aucune année de recommandation, dose ou seuil inventé.';
}
