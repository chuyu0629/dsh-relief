const fs=require('fs'),path=require('path');
const home=process.env.USERPROFILE||'C:\\Users\\Administrator';
const base=path.join(home,'.dsh','profiles','desktop');
const nm=path.join(base,'node_modules');
let pkg={};
try{pkg=JSON.parse(fs.readFileSync(path.join(base,'package.json'),'utf8'));}catch(e){process.exit(0);}
const deps=Object.keys(pkg.dependencies||{});
const scan=()=>{const list=[];if(!fs.existsSync(nm))return list;
 for(const e of fs.readdirSync(nm,{withFileTypes:true})){
  if(!e.isDirectory()||e.name.startsWith('.'))continue;
  if(e.name.startsWith('@')){for(const s of fs.readdirSync(path.join(nm,e.name),{withFileTypes:true})) if(s.isDirectory()) list.push(e.name+'/'+s.name);}
  else list.push(e.name);
 }return list;};
const all=scan();
const referenced=new Set();
for(const n of all){try{const j=JSON.parse(fs.readFileSync(path.join(nm,n,'package.json'),'utf8'));
 for(const k of ['dependencies','optionalDependencies','peerDependencies']) for(const d of Object.keys(j[k]||{})) referenced.add(d);}catch(e){}}
const out=[];
for(const n of all){
  if(deps.includes(n)||n.startsWith('@deepseek-ai/')||referenced.has(n)||referenced.has(n.split('/').pop()))continue;
  try{const j=JSON.parse(fs.readFileSync(path.join(nm,n,'package.json'),'utf8'));
   if(j.dsh&&(j.dsh.client||j.dsh.bundle)) out.push(n);}catch(e){}
}
console.log(JSON.stringify(out));
