/** Convert a provider's surplus distractors to the four-option QCU UI format. */
export function fourOptionQcu(options:string[],correct:number):{options:string[];correct:number}{
 if(options.length<=4||!Number.isInteger(correct)||correct<0||correct>=options.length)
  return {options,correct};
 const indexes=[0,1,2,3];
 if(correct>3)indexes[3]=correct;
 return {options:indexes.map(i=>options[i]),correct:indexes.indexOf(correct)};
}
