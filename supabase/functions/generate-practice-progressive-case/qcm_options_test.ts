import {fourOptionQcu} from './qcm_options.ts';
function equal(a:unknown,b:unknown){if(JSON.stringify(a)!==JSON.stringify(b))throw Error('Mismatch');}
Deno.test('four options remain unchanged',()=>equal(fourOptionQcu(['A','B','C','D'],2),{options:['A','B','C','D'],correct:2}));
Deno.test('surplus distractor removed while keeping answer',()=>equal(fourOptionQcu(['A','B','C','D','E'],1),{options:['A','B','C','D'],correct:1}));
Deno.test('correct fifth option preserved with new index',()=>equal(fourOptionQcu(['A','B','C','D','E'],4),{options:['A','B','C','E'],correct:3}));
Deno.test('incomplete choices not invented',()=>equal(fourOptionQcu(['A','B','C'],2),{options:['A','B','C'],correct:2}));
