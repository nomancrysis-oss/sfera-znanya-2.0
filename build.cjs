// Vercel serves public/ and deploys api/config.js as a managed function.
// No npm dependencies, bundler or manually managed server are needed.
const fs=require('node:fs');
const path=require('node:path');
const root=__dirname, out=path.join(root,'public');
fs.mkdirSync(out,{recursive:true});
for(const name of fs.readdirSync(root)){
  if(name.endsWith('.html')||name==='LICENSE-QR.txt'||name==='sfera-mobile-qr.png'||name==='chemistry-modo.css'||name==='chemistry-modo.js'||name==='geolab-data.js')fs.copyFileSync(path.join(root,name),path.join(out,name));
}
console.log('Static pages ready in public/');
