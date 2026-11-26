var k0=Object.defineProperty;var _0=(bt,it,Rt)=>it in bt?k0(bt,it,{enumerable:!0,configurable:!0,writable:!0,value:Rt}):bt[it]=Rt;var F=(bt,it,Rt)=>_0(bt,typeof it!="symbol"?it+"":it,Rt);(function(){"use strict";var Lo,Ro;function N(o){return Math.round(o*4)+1}function k(o,...t){if(t.length!==5)throw new Error(`palette ${o} needs 5 colors`);return{id:o,colors:t}}function Ae(o){const t=o.replace("#",""),e=parseInt(t.length===3?t.replace(/(.)/g,"$1$1"):t,16);return[e>>16&255,e>>8&255,e&255]}function To(o,t,e){o/=255,t/=255,e/=255;const a=Math.max(o,t,e),n=Math.min(o,t,e),r=(a+n)/2;if(a===n)return[0,0,r];const i=a-n,s=r>.5?i/(2-a-n):i/(a+n);let l;return a===o?l=(t-e)/i+(t<e?6:0):a===t?l=(e-o)/i+2:l=(o-t)/i+4,[l*60,s,r]}function Tt(o,t,e){o=(o%360+360)%360,t=Math.min(1,Math.max(0,t)),e=Math.min(1,Math.max(0,e));const a=(1-Math.abs(2*e-1))*t,n=a*(1-Math.abs(o/60%2-1)),r=e-a/2,[i,s,l]=o<60?[a,n,0]:o<120?[n,a,0]:o<180?[0,a,n]:o<240?[0,n,a]:o<300?[n,0,a]:[a,0,n],c=f=>Math.round((f+r)*255).toString(16).padStart(2,"0");return`#${c(i)}${c(s)}${c(l)}`}function Ct(o,t,e){const a=(t-o+540)%360-180;return o+Math.sign(a)*Math.min(Math.abs(a),e)}function v(o,t){const[e,a,n]=To(...Ae(t));return{id:o,colors:[Tt(Ct(e,255,22),a*.95+.05,n*.36),Tt(Ct(e,255,12),a*1.02,n*.68),Tt(e,a,n),Tt(Ct(e,50,8),a*.95,n+(1-n)*.3),Tt(Ct(e,50,14),a*.85,n+(1-n)*.58)]}}const Se=new WeakMap,le=o=>o<=.04045?o/12.92:((o+.055)/1.055)**2.4,Ho=o=>o<=.0031308?o*12.92:1.055*o**(1/2.4)-.055;function Fo([o,t,e]){const a=le(o/255),n=le(t/255),r=le(e/255),i=Math.cbrt(.4122214708*a+.5363325363*n+.0514459929*r),s=Math.cbrt(.2119034982*a+.6806995451*n+.1073969566*r),l=Math.cbrt(.0883024619*a+.2817188376*n+.6299787005*r);return[.2104542553*i+.793617785*s-.0040720468*l,1.9779984951*i-2.428592205*s+.4505937099*l,.0259040371*i+.7827717662*s-.808675766*l]}function Ie([o,t,e]){const a=(o+.3963377774*t+.2158037573*e)**3,n=(o-.1055613458*t-.0638541728*e)**3,r=(o-.0894841775*t-1.291485548*e)**3,i=4.0767416621*a-3.3077115913*n+.2309699292*r,s=-1.2684380046*a+2.6097574011*n-.3413193965*r,l=-.0041960863*a-.7034186147*n+1.707614701*r,c=f=>Math.max(0,Math.min(255,Math.round(Ho(Math.max(0,Math.min(1,f)))*255)));return[c(i),c(s),c(l)]}function Eo(o){let t=Se.get(o);if(!t){t=new Uint8Array(21*3);const a=o.colors.map(r=>Fo(Ae(r)));for(let r=0;r<=4*4;r++){const i=Math.min(3,Math.floor(r/4)),s=r/4-i,l=a[i],c=a[i+1];t.set(Ie([l[0]+(c[0]-l[0])*s,l[1]+(c[1]-l[1])*s,l[2]+(c[2]-l[2])*s]),r*3)}const n=Ie(a[0].map((r,i)=>r*.55+a[1][i]*.45));t.set(n,5*4*3),Se.set(o,t)}return t}class qt{constructor(t,e){F(this,"idx");F(this,"pid");F(this,"palettes",[]);F(this,"cur",0);F(this,"x0",0);F(this,"y0",0);F(this,"x1",-1);F(this,"y1",-1);F(this,"dark");this.w=t,this.h=e,this.idx=new Uint8Array(t*e),this.pid=new Uint8Array(t*e)}clear(){return this.idx.fill(0),this.palettes.length=0,this.cur=0,this.x0=this.y0=0,this.x1=this.y1=-1,this}touch(t,e){if(this.x1<this.x0){this.x0=this.x1=t,this.y0=this.y1=e;return}t<this.x0?this.x0=t:t>this.x1&&(this.x1=t),e<this.y0?this.y0=e:e>this.y1&&(this.y1=e)}use(t){let e=this.palettes.indexOf(t);return e<0&&(this.palettes.push(t),e=this.palettes.length-1),this.cur=e,this}px(t,e,a){if(t=Math.round(t),e=Math.round(e),t<0||e<0||t>=this.w||e>=this.h)return;const n=e*this.w+t;if(a<0){this.idx[n]=0;return}this.idx[n]=N(a),this.pid[n]=this.cur,this.touch(t,e)}reshade(t,e,a){if(t<0||e<0||t>=this.w||e>=this.h)return;const n=e*this.w+t;if(!this.idx[n])return;const r=(this.idx[n]-1)/4;r<1||r>4||(this.idx[n]=N(Math.max(1,Math.min(4,r+a))))}get(t,e){if(t<0||e<0||t>=this.w||e>=this.h)return-1;const a=this.idx[e*this.w+t];return a?(a-1)/4:-1}rect(t,e,a,n,r){t=Math.round(t),e=Math.round(e);for(let i=0;i<n;i++)for(let s=0;s<a;s++)this.px(t+s,e+i,r)}hline(t,e,a,n){t=Math.round(t),e=Math.round(e);for(let r=Math.min(t,e);r<=Math.max(t,e);r++)this.px(r,a,n)}line(t,e,a,n,r){t=Math.round(t),e=Math.round(e),a=Math.round(a),n=Math.round(n);const i=Math.abs(a-t),s=-Math.abs(n-e),l=t<a?1:-1,c=e<n?1:-1;let f=i+s;for(;this.px(t,e,r),!(t===a&&e===n);){const h=2*f;h>=s&&(f+=s,t+=l),h<=i&&(f+=i,e+=c)}}fill(t,e,a,n,r){for(let i=Math.round(e);i<=Math.round(n);i++)for(let s=Math.round(t);s<=Math.round(a);s++){const l=r(s,i);l>=0&&this.px(s,i,l)}}ellipse(t,e,a,n,r){this.fill(t-a-1,e-n-1,t+a+1,e+n+1,(i,s)=>{const l=(i-t)/a,c=(s-e)/n;return l*l+c*c<=1?r:-1})}stamp(t,e,a){e=Math.round(e),a=Math.round(a),t.forEach((n,r)=>{for(let i=0;i<n.length;i++){const s=n.charCodeAt(i)-48;s>=0&&s<=4&&this.px(e+i,a+r,s)}})}outline(){const{w:t,h:e,idx:a,pid:n}=this;if(this.x1<this.x0)return;const r=a.slice(),i=Math.max(0,this.x0-1),s=Math.min(t-1,this.x1+1),l=Math.max(0,this.y0-1),c=Math.min(e-1,this.y1+1);for(let f=l;f<=c;f++)for(let h=i;h<=s;h++){const d=f*t+h;if(r[d])continue;const w=h>0&&r[d-1]>0,p=f>0&&r[d-t]>0,u=h<t-1&&r[d+1]>0,m=f<e-1&&r[d+t]>0;if(!w&&!p&&!u&&!m)continue;const y=!p&&(!w||u);a[d]=N(y?5:0),n[d]=n[w?d-1:p?d-t:u?d+1:d+t]}this.x0=i,this.x1=s,this.y0=l,this.y1=c}closeHoles(t=1,e=2){const{w:a,h:n,idx:r,pid:i}=this,s=Math.max(1,this.x0),l=Math.min(a-2,this.x1),c=Math.max(1,this.y0),f=Math.min(n-2,this.y1);for(let h=0;h<e;h++){const d=r.slice();for(let w=c;w<=f;w++)for(let p=s;p<=l;p++){const u=w*a+p;if(d[u])continue;const m=d[u-1],y=d[u+1],g=d[u-a],_=d[u+a];(m?1:0)+(y?1:0)+(g?1:0)+(_?1:0)<3&&!(m&&y)&&!(g&&_)||(r[u]=N(t),i[u]=i[m?u-1:y?u+1:g?u-a:u+a])}}}fillInteriorOutlines(t,e){const{w:a,h:n,idx:r,pid:i,palettes:s}=this,l=N(0),c=N(5),f=d=>d>0&&d!==l&&d!==c,h=r.slice();for(let d=1;d<n-1;d++)for(let w=1;w<a-1;w++){const p=d*a+w;if(h[p]!==l&&h[p]!==c||!e.includes(s[i[p]]))continue;const u=[h[p-1],h[p+1],h[p-a],h[p+a]];u.every(m=>m>0)&&u.filter(f).length>=2&&(r[p]=N(h[p]===l?t:t+.5))}}bounce(t=.5,e=.6,a=1.9){const{w:n,h:r,idx:i}=this,s=i.slice();for(let l=Math.max(0,this.y0);l<=this.y1;l++)for(let c=Math.max(0,this.x0);c<=this.x1;c++){const f=l*n+c;if(!s[f]||!(c===n-1||!s[f+1]||l===r-1||!s[f+n]))continue;const d=(s[f]-1)/4;d<e||d>a||(i[f]=N(Math.min(a,d+t)))}}castShadow(t,e){const{w:a,h:n}=this;if(t.x1<t.x0)return;(!this.dark||this.dark.length!==a*n)&&(this.dark=new Float32Array(a*n));const r=this.dark;let i=0;for(const[c,f]of e)i=Math.max(i,c,f);const s=Math.min(a-1,t.x1+i),l=Math.min(n-1,t.y1+i);for(let c=t.y0;c<=l;c++)r.fill(0,c*a+t.x0,c*a+s+1);for(let c=t.y0;c<=t.y1;c++)for(let f=t.x0;f<=t.x1;f++){const h=t.idx[c*a+f];if(!(!h||h===N(0)||h===N(5)))for(const[d,w,p]of e){const u=f+d,m=c+w;if(u<0||m<0||u>=a||m>=n)continue;const y=m*a+u;r[y]<p&&(r[y]=p)}}for(let c=t.y0;c<=l;c++)for(let f=t.x0;f<=s;f++){const h=c*a+f;if(!r[h]||t.idx[h]||!this.idx[h])continue;const d=(this.idx[h]-1)/4;d<=0+.25||d>4||(this.idx[h]=N(Math.max(.25,d-r[h])))}}drawOnto(t,e=0,a=0,n,r=!1){const i=N(0),s=N(5),l=this.palettes.map(c=>{let f=t.palettes.indexOf(c);return f<0&&(t.palettes.push(c),f=t.palettes.length-1),f});for(let c=Math.max(0,this.y0);c<=this.y1;c++){const f=c+a;if(!(f<0||f>=t.h))for(let h=Math.max(0,this.x0);h<=this.x1;h++){const d=this.idx[c*this.w+h];if(!d)continue;const w=h+e;if(w<0||w>=t.w)continue;const p=f*t.w+w,u=t.idx[p];r&&(!u||u===i||u===s)||(n!==void 0&&(d===i||d===s)&&u&&u!==i&&u!==s?t.idx[p]=N(d===i?n:n+.5):t.idx[p]=d,t.pid[p]=l[this.pid[c*this.w+h]],t.touch(w,f))}}}toRGBA(t){const e=this.palettes.map(Eo);for(let a=0;a<this.idx.length;a++){const n=this.idx[a],r=a*4;if(!n){t[r]=t[r+1]=t[r+2]=t[r+3]=0;continue}const i=e[this.pid[a]],s=(n-1)*3;t[r]=i[s],t[r+1]=i[s+1],t[r+2]=i[s+2],t[r+3]=255}}}const Le=Object.fromEntries(["cape","weapon_back","arm_back","legs","bottom","shoes","torso","top","bag","arm_front","mantle","weapon_mid","hair_back","head","scarf","hair","weapon_front"].map((o,t)=>[o,t*10])),Re={clips:{attack1:[{head:[7.05,28],neck:[3.55,24],hip:[.32,17.27],armNear:{root:[3.05,23],joint:[-1.45,23],end:[-7.95,28]},armFar:{root:[6.05,20],joint:[6.05,17.5],end:[11.05,13]},legA:{root:[1.05,14],joint:[-1.55,8.4],end:[-7.95,0]},legB:{root:[3.05,14],joint:[6.65,8.4],end:[11.05,0]},sword:{hilt:[-9.45,28.5],tip:[-24.45,19.5]},smear:0},{head:[7.7,26.66],neck:[5.05,23],hip:[.47,17.24],armNear:{root:[5.05,22],joint:[7.55,19],end:[15.05,18]},armFar:null,legA:{root:[1.05,14],joint:[2.45,8.4],end:[-3.95,0]},legB:{root:[4.05,14],joint:[5.55,8.5],end:[3.05,0]},sword:null,smear:569},{head:[9.05,26],neck:[2.83,23.07],hip:[.47,17.24],armNear:{root:[3.05,22],joint:[6.05,17.5],end:[13.05,14]},armFar:{root:[.05,22],joint:[-.95,20.5],end:[-5.95,13]},legA:{root:[1.05,14],joint:[4.65,9.4],end:[9.05,0]},legB:{root:[-2.95,12],joint:[-1.55,9.4],end:[-7.95,0]},sword:null,smear:319},{head:[9.05,26],neck:[2.55,23],hip:[.36,17.27],armNear:{root:[4.05,21],joint:[7.45,16.4],end:[6.05,14]},armFar:{root:[.05,22],joint:[.05,21.5],end:[-6.95,16]},legA:{root:[1.05,14],joint:[5.65,9.4],end:[12.05,0]},legB:{root:[-1.95,14],joint:[-2.55,9.4],end:[-8.95,0]},sword:null,smear:196},{head:[10.05,25],neck:[3.8,22],hip:[.33,17.2],armNear:{root:[5.05,21],joint:[6.55,16],end:[7.05,14]},armFar:{root:[3.05,23],joint:[.55,22],end:[-7.95,16]},legA:{root:[1.05,14],joint:[5.65,9.4],end:[12.05,0]},legB:{root:[-1.95,14],joint:[-2.55,9.4],end:[-8.95,0]},sword:null,smear:113},{head:[10.05,25],neck:[3.8,22],hip:[.2,17.23],armNear:{root:[5.05,21],joint:[6.05,16.5],end:[5.05,14]},armFar:{root:[3.05,23],joint:[.55,22],end:[-8.95,18]},legA:{root:[1.05,14],joint:[5.65,9.4],end:[12.05,0]},legB:{root:[-1.95,14],joint:[-2.55,9.4],end:[-8.95,0]},sword:null,smear:57},{head:[10.05,25],neck:[3.8,22],hip:[.2,17.23],armNear:{root:[5.05,21],joint:[6.05,16.5],end:[5.05,14]},armFar:{root:[3.05,23],joint:[.55,22],end:[-8.95,18]},legA:{root:[1.05,14],joint:[5.65,9.4],end:[12.05,0]},legB:{root:[-1.95,14],joint:[-2.55,9.4],end:[-8.95,0]},sword:{hilt:[-5.45,12.5],tip:[-17.45,7.5]},smear:0},{head:[10.05,25],neck:[3.55,22],hip:[.33,17.2],armNear:{root:[5.05,20],joint:[7.05,16.5],end:[6.05,14]},armFar:{root:[4.05,23],joint:[1.38,22.33],end:[-7.95,18]},legA:{root:[1.05,14],joint:[5.65,9.4],end:[12.05,0]},legB:{root:[-1.95,14],joint:[-2.55,9.4],end:[-8.95,0]},sword:{hilt:[4.55,14.5],tip:[-17.45,8.5]},smear:0}],attack2:[{head:[9.05,26],neck:[2.55,23],hip:[.36,17.27],armNear:{root:[4.05,21],joint:[7.45,16.4],end:[6.05,14]},armFar:{root:[.05,22],joint:[.05,21.5],end:[-6.95,16]},legA:{root:[1.05,14],joint:[4.65,9.4],end:[9.05,0]},legB:{root:[-2.95,12],joint:[-1.55,9.4],end:[-7.95,0]},sword:{hilt:[5.55,13.5],tip:[-14.45,4.5]},smear:0},{head:[6.94,26.74],neck:[3.05,24],hip:[.32,17.27],armNear:{root:[2.05,23],joint:[.25,23.8],end:[-.95,28]},armFar:null,legA:{root:[1.05,14],joint:[2.45,8.4],end:[-3.95,0]},legB:{root:[4.05,14],joint:[5.55,8.5],end:[3.05,0]},sword:{hilt:[-1.45,29.5],tip:[1.55,28.5]},smear:483},{head:[6.05,28],neck:[3.05,24],hip:[.32,17.27],armNear:{root:[2.05,23],joint:[-2.45,23],end:[-9.95,26]},armFar:{root:[5.05,19],joint:[4.72,17.33],end:[8.05,12]},legA:{root:[1.05,14],joint:[-1.55,8.4],end:[-7.95,0]},legB:{root:[3.05,14],joint:[6.65,8.4],end:[11.05,0]},sword:null,smear:366},{head:[5.05,29],neck:[3.55,24],hip:[.32,17.27],armNear:null,armFar:{root:[6.05,20],joint:[6.05,17.5],end:[11.05,13]},legA:{root:[1.05,14],joint:[-1.55,8.4],end:[-7.95,0]},legB:{root:[3.05,14],joint:[6.65,8.4],end:[11.05,0]},sword:null,smear:244},{head:[5.05,29],neck:[3.55,24],hip:[.32,17.27],armNear:null,armFar:{root:[6.05,20],joint:[6.05,17.5],end:[12.05,16]},legA:{root:[1.05,14],joint:[-1.55,8.4],end:[-7.95,0]},legB:{root:[3.05,14],joint:[6.65,8.4],end:[11.05,0]},sword:null,smear:161},{head:[5.05,29],neck:[3.55,24],hip:[.32,17.27],armNear:{root:[3.05,23],joint:[-3.45,21],end:[-10.95,24]},armFar:{root:[5.05,19],joint:[6.05,18],end:[12.05,21]},legA:{root:[1.05,14],joint:[-1.55,8.4],end:[-7.95,0]},legB:{root:[3.05,14],joint:[6.65,8.4],end:[11.05,0]},sword:null,smear:80},{head:[5.05,29],neck:[3.55,24],hip:[.32,17.27],armNear:{root:[3.05,23],joint:[-2.15,21.8],end:[-10.95,22]},armFar:{root:[5.05,19],joint:[6.05,18],end:[12.05,22]},legA:{root:[1.05,14],joint:[-1.55,8.4],end:[-7.95,0]},legB:{root:[3.05,14],joint:[6.65,8.4],end:[11.05,0]},sword:{hilt:[-12.45,22.5],tip:[-28.45,27.5]},smear:0},{head:[5.05,29],neck:[3.55,24],hip:[.32,17.27],armNear:{root:[3.05,23],joint:[-1.78,21.67],end:[-9.95,22]},armFar:{root:[6.05,20],joint:[6.05,19],end:[12.05,23]},legA:{root:[1.05,14],joint:[-1.55,8.4],end:[-7.95,0]},legB:{root:[3.05,14],joint:[6.65,8.4],end:[11.05,0]},sword:{hilt:[-11.45,22.5],tip:[-29.45,26.5]},smear:0}],attack3:[{head:[8.11,28.26],neck:[3.05,21.83],hip:[.36,17.27],armNear:{root:[3.05,21],joint:[6.05,26.5],end:[1.05,32]},armFar:null,legA:{root:[1.05,14],joint:[-1.55,8.4],end:[-7.95,0]},legB:{root:[3.05,14],joint:[6.65,8.4],end:[11.05,0]},sword:{hilt:[-.45,30.5],tip:[-19.45,23.5]},smear:0},{head:[8.05,27],neck:[1.55,23],hip:[.47,17.24],armNear:{root:[3.05,22],joint:[9.38,20.33],end:[16.05,24]},armFar:{root:[6.05,18],joint:[9.72,17.67],end:[15.05,21]},legA:{root:[1.05,14],joint:[-1.55,8.4],end:[-7.95,0]},legB:{root:[3.05,14],joint:[6.65,8.4],end:[11.05,0]},sword:null,smear:365},{head:[9.05,26],neck:[4.55,23],hip:[1.05,16.83],armNear:{root:[4.05,22],joint:[1.05,19],end:[1.05,13]},armFar:{root:[6.05,19],joint:[6.05,19],end:[4.05,14]},legA:{root:[.05,14],joint:[-3.95,8.5],end:[-7.95,0]},legB:{root:[1.05,11],joint:[2.05,10.67],end:[14.05,0]},sword:null,smear:698},{head:[10.05,25],neck:[4.55,23],hip:[.64,16.85],armNear:{root:[4.05,22],joint:[-.28,19.67],end:[-4.95,15]},armFar:{root:[6.05,19],joint:[6.05,18],end:[2.05,12]},legA:null,legB:{root:[2.05,14],joint:[8.05,8.5],end:[14.05,0]},sword:null,smear:188},{head:[10.05,25],neck:[4.55,23],hip:[.55,17.02],armNear:{root:[4.05,22],joint:[-1.45,20],end:[-6.95,17]},armFar:{root:[6.05,19],joint:[6.55,18],end:[3.05,13]},legA:{root:[1.05,14],joint:[-3.95,8.5],end:[-7.95,0]},legB:{root:[2.05,14],joint:[8.05,8.5],end:[14.05,0]},sword:null,smear:101},{head:[10.05,25],neck:[4.55,23],hip:[.51,17.12],armNear:{root:[4.05,22],joint:[-.45,21],end:[-7.95,18]},armFar:{root:[6.05,19],joint:[6.55,18],end:[4.05,13]},legA:{root:[1.05,14],joint:[-3.95,8.5],end:[-7.95,0]},legB:{root:[2.05,14],joint:[8.05,8.5],end:[14.05,0]},sword:null,smear:66},{head:[10.05,25],neck:[4.55,23],hip:[.51,17.12],armNear:{root:[4.05,22],joint:[-.45,21],end:[-7.95,18]},armFar:{root:[6.05,19],joint:[7.05,16.5],end:[10.05,12]},legA:{root:[1.05,14],joint:[-3.95,8.5],end:[-7.95,0]},legB:{root:[2.05,14],joint:[8.05,8.5],end:[14.05,0]},sword:{hilt:[-8.45,17.5],tip:[-27.45,11.5]},smear:0},{head:[9.05,26],neck:[4.55,23],hip:[.51,17.12],armNear:{root:[4.05,22],joint:[.25,21.2],end:[-6.95,19]},armFar:{root:[7.05,20],joint:[6.8,17.75],end:[12.05,13]},legA:{root:[1.05,14],joint:[-3.95,8.5],end:[-7.95,0]},legB:{root:[2.05,14],joint:[8.05,8.5],end:[14.05,0]},sword:{hilt:[-7.45,18.5],tip:[-28.45,14.5]},smear:0}],dash:[{head:[9.05,26],neck:[3.05,22],hip:[.72,16.8],armNear:{root:[5.05,21],joint:[9.42,20.38],end:[12.05,20]},armFar:{root:[2.05,22],joint:[-2.45,20],end:[-7.95,16]},legA:{root:[1.05,14],joint:[-2.35,8.6],end:[-6.95,0]},legB:{root:[3.05,14],joint:[3.65,9.6],end:[-2.95,5]},sword:{hilt:[4.55,25.5],tip:[-15.45,31.5]},smear:0},{head:[8.05,25],neck:[2.55,21],hip:[.17,16.31],armNear:{root:[4.05,19],joint:[8.55,17],end:[15.05,14]},armFar:{root:[.05,20],joint:[-.95,18.5],end:[-3.95,13]},legA:{root:[1.05,14],joint:[-3.35,8.6],end:[-8.95,0]},legB:{root:[2.05,14],joint:[4.65,9.6],end:[-2.95,5]},sword:null,smear:576},{head:[7.05,25],neck:[3.05,21],hip:[-.24,16.29],armNear:null,armFar:null,legA:{root:[.05,14],joint:[-4.35,8.6],end:[-9.95,0]},legB:{root:[2.05,14],joint:[4.65,9.6],end:[-1.95,4]},sword:null,smear:479},{head:[6.05,26],neck:[2.05,21.9],hip:[.32,16.35],armNear:{root:[-.95,21],joint:[-4.95,18.5],end:[-9.95,16]},armFar:{root:[6.05,18],joint:[5.72,15.33],end:[9.05,10]},legA:{root:[1.05,14],joint:[-4.75,9.2],end:[-9.95,0]},legB:{root:[2.05,14],joint:[5.05,9.5],end:[5.05,5]},sword:{hilt:[-10.45,15.5],tip:[-13.45,17.5]},smear:321},{head:[5.05,26],neck:[1.88,21.83],hip:[.32,16.35],armNear:{root:[.05,22],joint:[-3.95,19.5],end:[-8.95,17]},armFar:{root:[6.05,20],joint:[6.45,17.6],end:[12.05,11]},legA:{root:[1.05,14],joint:[-4.75,9.2],end:[-9.95,0]},legB:{root:[2.05,14],joint:[6.45,8.6],end:[8.05,0]},sword:{hilt:[-9.45,16.5],tip:[-12.45,18.5]},smear:153},{head:[3.05,27],neck:[-.45,21.92],hip:[-.63,16.14],armNear:{root:[-3.95,21],joint:[-4.2,20.25],end:[-11.95,18]},armFar:{root:[4.05,20],joint:[4.45,17.6],end:[11.05,12]},legA:{root:[-.95,14],joint:[-5.95,9.5],end:[-9.95,0]},legB:{root:[.05,14],joint:[6.65,8.4],end:[13.05,0]},sword:{hilt:[-12.45,17.5],tip:[-15.45,19.5]},smear:89},{head:[1.05,27],neck:[-.45,21.92],hip:[-.63,16.14],armNear:{root:[-3.95,21],joint:[-4.2,20.25],end:[-11.95,18]},armFar:{root:[4.05,20],joint:[4.45,17.6],end:[11.05,12]},legA:{root:[-.95,14],joint:[-5.95,9.5],end:[-9.95,0]},legB:{root:[.05,14],joint:[5.45,9.6],end:[11.05,0]},sword:{hilt:[-12.45,17.5],tip:[-34.45,14.5]},smear:0},{head:[1.05,28],neck:[-.45,21.92],hip:[-.63,16.14],armNear:{root:[-2.95,22],joint:[-5.55,20.4],end:[-12.95,17]},armFar:{root:[3.05,22],joint:[4.55,17],end:[10.05,12]},legA:{root:[-.95,14],joint:[-5.95,9.5],end:[-9.95,0]},legB:{root:[.05,14],joint:[4.05,9.5],end:[9.05,0]},sword:{hilt:[-13.45,16.5],tip:[-35.45,13.5]},smear:0}],hurt:[{head:[4.04,26.45],neck:[.35,22.9],hip:[-1.45,17.17],armNear:{root:[-.95,22],joint:[-3.52,21.21],end:[-4.95,17]},armFar:null,legA:{root:[-2.95,15],joint:[-1.28,8.33],end:[-4.95,0]},legB:{root:[2.05,15],joint:[4.55,10.5],end:[11.05,1]},sword:null,smear:149},{head:[3.12,26.97],neck:[-.95,24],hip:[.55,17.5],armNear:{root:[-1.95,23],joint:[-3.45,19],end:[3.05,14]},armFar:{root:[3.05,19],joint:[3.05,19],end:[9.05,16]},legA:{root:[-.95,14],joint:[.55,8],end:[-2.95,0]},legB:{root:[.05,14],joint:[4.65,10.4],end:[9.05,1]},sword:null,smear:77},{head:[.08,28.85],neck:[-2.45,24.93],hip:[-3.33,18.5],armNear:{root:[-1.95,24],joint:[-1.45,21],end:[5.05,17]},armFar:null,legA:{root:[-2.95,16],joint:[.05,8.5],end:[4.05,0]},legB:{root:[1.05,16],joint:[3.45,11.6],end:[8.05,2]},sword:null,smear:29},{head:[-.95,30],neck:[-2.55,25],hip:[-3.45,18.68],armNear:{root:[-1.95,24],joint:[-.35,19.4],end:[5.05,13]},armFar:null,legA:{root:[-2.95,16],joint:[3.05,8.5],end:[7.05,0]},legB:null,sword:null,smear:12},{head:[-1.95,30],neck:[-1.55,24],hip:[-.75,17.9],armNear:{root:[-.95,23],joint:[.05,17.5],end:[4.05,11]},armFar:null,legA:{root:[-.95,15],joint:[3.65,8.4],end:[8.05,0]},legB:{root:[-1.95,15],joint:[-1.95,8],end:[-5.95,0]},sword:null,smear:0},{head:[-.95,30],neck:[-.55,24],hip:[.15,17.8],armNear:{root:[.05,23],joint:[.05,16.5],end:[2.05,10]},armFar:{root:[-2.95,20],joint:[-2.95,18],end:[-3.95,15]},legA:{root:[2.05,15],joint:[2.65,9.4],end:[6.05,0]},legB:{root:[-1.95,15],joint:[-2.35,8.6],end:[-5.95,0]},sword:null,smear:0},{head:[1.05,32],neck:[.85,26],hip:[1.32,18.23],armNear:{root:[.05,25],joint:[-1.95,20.5],end:[-2.95,13]},armFar:null,legA:{root:[2.05,15],joint:[2.65,9.4],end:[7.05,0]},legB:{root:[4.05,15],joint:[.55,8.5],end:[-2.95,0]},sword:null,smear:0},{head:[.05,30],neck:[.05,24],hip:[-.72,17.91],armNear:{root:[-1.95,23],joint:[-4.95,19.5],end:[-5.95,12]},armFar:{root:[3.05,19],joint:[3.05,19],end:[6.05,12]},legA:{root:[.05,15],joint:[-2.55,8.4],end:[-5.95,0]},legB:{root:[2.05,15],joint:[3.45,9.4],end:[4.05,0]},sword:null,smear:0}],die:[{head:[7.05,27],neck:[4.55,22],hip:null,armNear:{root:[4.05,21],joint:[-.95,18.5],end:[-5.95,13]},armFar:null,legA:null,legB:null,sword:null,smear:0},{head:[12.05,24],neck:[8.55,20],hip:null,armNear:{root:[8.05,19],joint:[2.72,17.67],end:[-4.95,14]},armFar:null,legA:null,legB:null,sword:null,smear:0},{head:[15.05,21],neck:[12.05,17],hip:null,armNear:{root:[12.05,16],joint:[6.55,16],end:[-2.95,17]},armFar:null,legA:null,legB:null,sword:null,smear:0},{head:[19.05,16],neck:[16.05,12],hip:null,armNear:{root:[16.05,11],joint:[8.55,13],end:[.05,17]},armFar:{root:[14.05,13],joint:[14.05,13],end:[4.05,17]},legA:null,legB:null,sword:null,smear:0},{head:[22.05,10],neck:[13.05,7.75],hip:null,armNear:{root:[13.05,7],joint:[11.85,8.2],end:[4.05,14]},armFar:null,legA:null,legB:null,sword:null,smear:0},{head:[23.05,6],neck:[18.05,5],hip:null,armNear:{root:[18.05,4],joint:[10.55,5],end:[3.05,10]},armFar:{root:[17.05,6],joint:[16.05,6],end:[10.05,11]},legA:null,legB:null,sword:null,smear:0},{head:[23.05,4],neck:[13.55,4.3],hip:null,armNear:{root:[14.05,3],joint:[10.55,2],end:[2.05,5]},armFar:null,legA:null,legB:null,sword:null,smear:0},{head:[24.05,3.29],neck:[18.05,3],hip:null,armNear:{root:[18.05,2],joint:[10.55,1],end:[2.05,1]},armFar:null,legA:null,legB:null,sword:null,smear:0},{head:[24.05,2.69],neck:[18.05,3],hip:null,armNear:{root:[18.05,2],joint:[10.05,1],end:[1.05,0]},armFar:null,legA:null,legB:null,sword:null,smear:0},{head:[24.05,2.69],neck:[18.05,3],hip:null,armNear:{root:[18.05,2],joint:[10.05,1],end:[1.05,1]},armFar:null,legA:null,legB:null,sword:null,smear:0},{head:[24.05,2.69],neck:[18.05,3],hip:null,armNear:{root:[18.05,2],joint:[10.05,1],end:[1.05,0]},armFar:null,legA:null,legB:null,sword:null,smear:0},{head:[24.05,2.69],neck:[18.05,3],hip:null,armNear:{root:[18.05,2],joint:[10.05,1],end:[1.05,0]},armFar:null,legA:null,legB:null,sword:null,smear:0}],idle:[{head:[.05,32],neck:[.05,25.93],hip:[0,18.11],armNear:{root:[-3.95,25],joint:[-5.95,19.5],end:[-6.95,12]},armFar:{root:[5.05,25],joint:[5.05,19],end:[8.05,12]},legA:{root:[.05,15],joint:[-2.55,9.4],end:[-5.95,0]},legB:{root:[2.05,15],joint:[4.05,9.5],end:[8.05,0]},sword:null,smear:0},{head:[.05,31.5],neck:[.05,25.93],hip:[0,18.11],armNear:{root:[-3.95,25],joint:[-5.95,19.5],end:[-6.95,12]},armFar:{root:[5.05,25],joint:[5.05,19],end:[8.05,12]},legA:{root:[.05,15],joint:[-2.55,9.4],end:[-5.95,0]},legB:{root:[2.05,15],joint:[4.05,9.5],end:[8.05,0]},sword:null,smear:0},{head:[.05,31],neck:[.05,25.93],hip:[-.01,17.66],armNear:{root:[-3.95,25],joint:[-5.95,18.5],end:[-5.95,11]},armFar:{root:[5.05,25],joint:[5.05,18],end:[7.05,11]},legA:{root:[.05,15],joint:[-2.55,9.4],end:[-5.95,0]},legB:{root:[2.05,15],joint:[3.65,9.4],end:[8.05,0]},sword:null,smear:0},{head:[.05,31],neck:[.05,24.93],hip:[-.01,17.66],armNear:{root:[-3.95,24],joint:[-5.95,18.5],end:[-6.95,11]},armFar:{root:[5.05,24],joint:[5.05,18],end:[8.05,11]},legA:{root:[.05,15],joint:[-2.55,9.4],end:[-5.95,0]},legB:{root:[2.05,15],joint:[3.65,9.4],end:[8.05,0]},sword:null,smear:0},{head:[.05,31],neck:[.05,24.93],hip:[-.01,17.66],armNear:{root:[-3.95,24],joint:[-5.95,18.5],end:[-6.95,11]},armFar:{root:[5.05,24],joint:[5.05,18],end:[8.05,11]},legA:{root:[.05,15],joint:[-2.55,9.4],end:[-5.95,0]},legB:{root:[2.05,15],joint:[3.65,9.4],end:[8.05,0]},sword:null,smear:0},{head:[.05,31],neck:[.05,25.93],hip:[-.01,17.66],armNear:{root:[-3.95,24],joint:[-5.95,18.5],end:[-6.95,11]},armFar:{root:[5.05,24],joint:[5.05,18],end:[8.05,11]},legA:{root:[.05,15],joint:[-2.55,9.4],end:[-5.95,0]},legB:{root:[2.05,15],joint:[3.65,9.4],end:[8.05,0]},sword:null,smear:0},{head:[.05,31.5],neck:[.05,25.93],hip:[0,18.11],armNear:{root:[-3.95,25],joint:[-5.95,19.5],end:[-5.95,11]},armFar:{root:[5.05,25],joint:[5.05,19],end:[7.05,11]},legA:{root:[.05,15],joint:[-2.55,9.4],end:[-5.95,0]},legB:{root:[2.05,15],joint:[4.05,9.5],end:[8.05,0]},sword:null,smear:0},{head:[.05,32],neck:[.05,25.93],hip:[0,18.11],armNear:{root:[-3.95,25],joint:[-5.95,19.5],end:[-6.95,12]},armFar:{root:[5.05,25],joint:[5.05,19],end:[8.05,12]},legA:{root:[.05,15],joint:[-2.55,9.4],end:[-5.95,0]},legB:{root:[2.05,15],joint:[4.05,9.5],end:[8.05,0]},sword:null,smear:0}]}}.clips,Ht={shoulderUp:29,shoulderSide:6.4,hipSide:3.2,arm:12.5,leg:15.5},Ft=Re.idle[0],No=Math.hypot(Ft.armNear.end[0]-Ft.armNear.root[0],Ft.armNear.end[1]-Ft.armNear.root[1]),ce=Ft.hip[1],Te=Ht.arm/No,Wt=Ht.leg/ce,he=(o,t,e)=>Math.max(t,Math.min(e,o));function He(o,t){const e=Math.hypot(o,t)||1;return[o/e,t/e]}function zt(o,t={}){var i,s,l,c,f,h,d,w,p;const e=Re[o];if(!e)throw new Error(`mocap clip ${o} missing`);const a=(i=t.pick)!=null?i:e.map((u,m)=>m),n=[];let r;for(const u of a){const m=e[u],y=(s=m.hip)!=null?s:[0,ce],g=(l=m.neck)!=null?l:[y[0],y[1]+8],_=he((g[0]-y[0])*.85*((c=t.leanGain)!=null?c:1),-3.5,6),x=he(y[0]*Wt*.6,-3,3)-_*.2,b=Math.max(0,ce-y[1])*Wt*1.6+((f=t.crouch)!=null?f:1.2),A=Ht.shoulderUp-b,j=_*.95,I=(h=t.reach)!=null?h:1,T=(R,E,U)=>{if(!(R!=null&&R.root)||!R.end)return U!=null?U:[E,A-11,j+1];const ht=(R.end[0]-R.root[0])*Te*I,M=(R.end[1]-R.root[1])*Te*I;return[E,A+M,j+ht]},K=T(m.armNear,-6.4,r==null?void 0:r.R),P=T(m.armFar,Ht.shoulderSide,r==null?void 0:r.L);let L=(d=r==null?void 0:r.dir)!=null?d:[.1,.4,.9];if((w=m.sword)!=null&&w.hilt&&m.sword.tip){const[R,E]=He(m.sword.tip[0]-m.sword.hilt[0],m.sword.tip[1]-m.sword.hilt[1]);L=[.1,E,R]}else if((p=m.armNear)!=null&&p.joint&&m.armNear.end){const[R,E]=He(m.armNear.end[0]-m.armNear.joint[0],m.armNear.end[1]-m.armNear.joint[1]);L=[.1,E,R]}const tt=(R,E,U)=>R!=null&&R.end?[E,Math.max(0,R.end[1]*Wt),he((R.end[0]-y[0])*Wt*.85,-7,8)+x]:U!=null?U:[E,0,0],at=[tt(m.legA,-3.2,r==null?void 0:r.feet[0]),tt(m.legB,Ht.hipSide,r==null?void 0:r.feet[1])],nt={R:K,L:P,dir:L,neckF:_,hipF:x,bob:b,feet:at,trail:m.smear>40};n.push(nt),r=nt}return n}const $o=64,Oo=96,pt=32,Et=90;let $=.65,G=Math.round($o*$),Y=Math.round(Oo*$);const Nt=["S","SE","E","NE","N"],Bo=["slash","heavy","dash","shoot","cast"],Fe=["guard","hurt","victory","defeat"],fe=[["idle",2],["walk",6],["ready",2],["slash",8],["heavy",8],["dash",8],["shoot",8],["cast",8],["guard",2],["hurt",6],["victory",2],["defeat",6]],$t=(()=>{const o={};let t=0;for(const[e,a]of fe)o[e]=Array.from({length:a},(n,r)=>t+r),t+=a;return o})(),Ot=fe.reduce((o,[,t])=>o+t,0),vo=$t.idle,Go=$t.walk,Ko=$t.ready,Po=Object.fromEntries(Bo.map(o=>[o,$t[o]])),Uo=Object.fromEntries(Fe.map(o=>[o,$t[o]])),Do={slash:2,heavy:3,dash:3,shoot:4,cast:4},Jt=100,Xo=Array.from({length:8},(o,t)=>Jt+t);function Yo(o){if(o>=Jt&&o<Jt+8)return{anim:"walk",t:o-Jt,walk8:!0};let t=0;for(const[e,a]of fe){if(o<t+a)return{anim:e,t:o-t};t+=a}return{anim:"idle",t:0}}const Co={S:[0,1],SE:[Math.SQRT1_2,Math.SQRT1_2],E:[1,0],NE:[Math.SQRT1_2,-Math.SQRT1_2],N:[0,-1]},Ee=16,ot=17,Bt=29,de=30,qo=41.8,xt=11.6,kt=10.9,Ne=.35,D=(o,t,e=-3.2,a=3.2)=>[[e,0,o],[a,0,t]];function Wo(){const o=(t,e,a,n,r,i,s,l=-.4)=>({R:t,L:e,dir:a,lean:0,bob:r,step:0,absolute:!0,neckF:n,hipF:l,feet:i,fx:s});return[o([-6,31,-3],[5,21,7],[0,1,.3],1,2.6,D(-5.4,4.6)),o([-3,27,6],[4.5,26,10],[0,1,.12],1.7,2.2,D(-5.4,5.6)),o([-5,30,0],[3.5,28,12],[0,1,.05],1,2.8,D(-5.4,5.6),"arrow"),o([-5.5,30.5,-2.2],[3.5,28.5,12.5],[0,1,.04],.8,3.1,D(-5.6,5.6),"arrow"),o([-8.5,32,-6.5],[3.5,30,11.5],[0,1,-.06],0,2.3,D(-6.4,5.2),"loose",-.9),o([-8.5,28,-5],[4,27,10],[0,1,.05],.4,2.2,D(-6.2,5)),o([-6,25,0],[4.5,24,9],[0,1,.2],.9,2.1,D(-5.6,4.8)),o([-4,24,2.5],[5,22,8],[0,1,.3],1.2,2,D(-5.4,4.6))]}function zo(){const o=(t,e,a,n,r,i,s,l=-.3,c=!1)=>({R:t,L:e,dir:a,lean:0,bob:r,step:0,absolute:!0,neckF:n,hipF:l,feet:i,fx:s,trail:c});return[o([-7,21,1],[4,25,5],[.05,.8,-.5],.4,3.2,D(-4,3.8),"glow"),o([-7.5,27,-3],[5,28,8],[.05,.95,-.3],0,2,D(-4,3.8),"glow"),o([-6.5,37,0],[6,32,6],[.05,1,.1],-.6,.6,D(-3.2,3),"glow",.2),o([-6,39,2],[6.5,34,4],[.05,1,.25],-.8,.2,D(-3.2,3),"glow",.3),o([-5,30,11],[7,24,1],[.05,.5,.86],3.2,2.6,D(-5.6,6.4),"burst",-1,!0),o([-5,27,10],[7,23,0],[.05,.45,.9],2.8,3,D(-5.6,6.4),"burst",-1),o([-6.5,25,7],[6,25,5],[.05,.8,.55],1.6,2.2,D(-4.6,5)),o([-7,24,5],[6,25,7],[.05,.9,.42],1.5,1.7,D(-3.8,4.2))]}function Qt(o){return o.map(t=>({R:t.R,L:t.L,dir:t.dir,lean:0,bob:t.bob,step:0,trail:t.trail,absolute:!0,neckF:t.neckF,hipF:t.hipF,feet:t.feet}))}const $e={slash:Qt(zt("attack1",{crouch:1.6,reach:1.3})),heavy:Qt(zt("attack3",{crouch:2.2,leanGain:1.1,reach:1.3})).map((o,t)=>t===3?{...o,fx:"burst"}:o),dash:Qt(zt("dash",{crouch:1.8,leanGain:1.15,reach:1.3})),shoot:Wo(),cast:zo()},Jo={down:{front:5.6,back:4.8,crouch:2.8,key:{R:[-6,22,6],L:[5.5,24,4.5],dir:[.15,.45,.88],lean:2.4,bob:0,step:0}},shoulder:{front:6.6,back:5.8,crouch:3.6,key:{R:[-3,21,5],L:[0,0,0],dir:[.1,.72,.68],lean:2,bob:0,step:0}},bow:{front:4.6,back:5.4,crouch:2,key:{R:[-4,24,2.5],L:[5,22,8],dir:[0,1,.3],lean:1.3,bob:0,step:0}},up:{front:4.2,back:3.8,crouch:1.7,key:{R:[-7,24,5],L:[6,25,7],dir:[.05,.9,.42],lean:1.6,bob:0,step:0}},none:{front:5,back:4.2,crouch:2.3,key:{R:[-4,26,6],L:[4.5,27,7.5],dir:[.14,.95,.1],lean:2.2,bob:0,step:0}}};function Qo(o,t,e){const a=t===1;switch(o){case"guard":{const n={lean:-.4,bob:a?1.2:.6,step:a?-1.2:-.4};return e==="bow"?{R:[-3,25,6],L:[4,28,8],dir:[.15,1,.1],...n}:e==="none"?{R:[-1,28,7],L:[1.5,27,7.5],dir:[.14,.95,.1],...n}:e==="up"?{R:[-4,26,7],L:[5,26,7],dir:[.9,.45,.1],...n}:{R:[-3,26,7.5],L:[4,25,6],dir:[.95,.3,.1],...n}}case"hurt":return Oe[Math.min(Oe.length-1,t)];case"victory":{const n={lean:.2,bob:a?.6:0,step:-2.6};return e==="bow"?{R:[-6,25,3],L:[5,38,2],dir:[0,1,.05],...n}:e==="none"?{R:[-6,39,1],L:[6,23,3],dir:[.14,.95,.1],...n}:{R:[-6,38,2],L:[6,23,3],dir:[.08,1,.12],...n}}case"defeat":return Be[Math.min(Be.length-1,t)]}}const Oe=Qt(zt("hurt",{pick:[0,1,2,3,5,7],crouch:1.2})),Vt={R:[-5.5,40,1.5],L:[5.5,39,1],dir:[.05,1,.05],lean:0,step:0,absolute:!0,neckF:.5,hipF:0,feet:[[-2.6,0,-.6],[2.6,0,.6]],lying:!0},Be=[{R:[-6,18,9],L:[6,19,8],dir:[.2,-.5,.85],lean:0,bob:2.4,step:0,absolute:!0,neckF:4.5,hipF:-1.2,feet:[[-3.2,0,-5],[3.2,0,4.5]]},{R:[-6,12,11],L:[6,13,10],dir:[.2,-.8,.6],lean:0,bob:6.5,step:0,absolute:!0,neckF:6,hipF:-2,feet:[[-3.2,0,-6],[3.2,0,3]]},{...Vt,bob:-3},{...Vt,bob:0},{...Vt,bob:-1},{...Vt,bob:0}],pe=2.6;function vt(o,t,e={}){var R,E,U,ht;const[a,n]=Co[o],{anim:r,t:i,walk8:s}=Yo(t),l=r==="walk",c=Jo[(R=e.armedR)!=null?R:"none"],f=Fe.includes(r),h=r==="ready"?{...c.key,bob:i===1?.7:0}:f?Qo(r,i,(E=e.armedR)!=null?E:"none"):r!=="idle"&&r!=="walk"?$e[r][i]:void 0,d=h&&r!=="ready"&&!f&&i>0?$e[r][i-1]:void 0,w=r==="heavy"||(r==="ready"||r==="guard")&&e.armedR==="shoulder";let p=0,u=0,m=0,y=0;if(l){const M=s?8:6;y=(i+.5)/M*Math.PI*2,p=Math.sin(y),u=Math.cos(y),m=i%(M/2)===1?1:0}else h?m=h.lying?0:h.absolute?h.bob:h.bob+c.crouch:m=i===1?1:0;const g=h?h.lean+(r==="ready"||f||h.absolute?0:c.key.lean*.5):l?1:0,_=(U=h==null?void 0:h.neckF)!=null?U:g*.95,x=(ht=h==null?void 0:h.hipF)!=null?ht:-g*.3,b=(M,S,C,X=Ne)=>{const H=C*n-M*a;return{x:pt+M*n+C*a,y:Et-S+H*X,near:H}},A=b(l||h?0:-.3,qo-m,_+g*.25),j=M=>{const[S,C,X]=M,H=S*n+X*a,B=X*n-S*a,et=-C+B*Ne,ft=Math.min(1,Math.hypot(H,et));return{angle:Math.atan2(et,H),nr:B,reach:.35+.65*Math.max(.25,ft)}},I=(M,S)=>{const C=b(7.2*M,Bt-m,_*.95,.12);let X,H,B=[.14*M,.95,.1],et,ft=S==="up"||S==="shoulder";const Lt=S==="bow";if(h&&(M<0||Lt||w)){let W=M<0?h.R:h.L;M>0&&w&&(W=[h.R[0]+h.dir[0]*pe,h.R[1]+h.dir[1]*pe,h.R[2]+h.dir[2]*pe]),X=b(W[0],W[1]-m,W[2]+_*.7),H=b((7.2*M+W[0])/2+1.4*M,(Bt+W[1])/2-1.6-m,(_*1.7+W[2])/2-.8),Lt?B=h.dir.map((se,je)=>je===0?se*M:se):M<0&&(B=h.dir,h.trail&&d&&(et=j(d.dir).angle),ft=ft||h.dir[1]>.4)}else if(h&&M>0)X=b(h.L[0],h.L[1]-m,h.L[2]+_*.7),H=b((7.2+h.L[0])/2+1.4,(Bt+h.L[1])/2-1.6-m,(_*1.7+h.L[2])/2-.8);else if(S==="up")H=b(8.6*M,ot+7-m,-1),X=b(9.6*M,ot+5-m,3.2+1.2*p*M),Math.abs(n)<.5&&(B=[B[0],B[1],.62]);else if(S==="down")H=b(8.5*M,ot+6.5-m,.5*p*M),X=b(8.8*M,ot+1.5-m,2.6+1.6*p*M),B=[.5*M,-.55,.65];else if(S==="shoulder")H=b(8.4*M,ot+6-m,1.5),X=b(5.5*M,ot+5-m,4+.6*p*M),B=[.55*M,.72,-.45];else if(S==="bow")H=b(8.4*M,(Bt+ot)/2+.5-m,-.6),X=b(8.6*M,ot+1.5-m,2.6+1.2*p*M),B=[.05*M,1,.12];else{const W=l?4.5*p*M:M<0?1.4:-.6;H=b(8.3*M,(Bt+ot)/2+.5-m,W*.35-1.2),X=b(7.8*M,ot-m+Math.abs(W)*.15,W+.8)}const dt=j(B),Yt=Math.abs(n)<.5;return{shoulder:C,elbow:H,hand:{...X,front:C.near>=-.01,angle:dt.angle,weaponFront:h&&Lt||(h||S==="shoulder"||S==="bow"?X.near+dt.nr*10>=-.5:-7.8*M*a+dt.nr*14>=-.5),weaponOverHead:Yt,weaponMid:ft&&!Yt,reach:S==="up"||S==="down"?h?dt.reach:1:dt.reach,trailFrom:et}}},T=e.armedR==="bow",K=I(-1,T?void 0:e.armedR),P=I(1,T?"bow":e.armedL),L=(M,S)=>{const C=Ee-m,X=b(2.8*S,C,x,0);let H,B,et;if(h)[H,B,et]=h.feet?h.feet[S<0?0:1]:S<0?[-3.4,0,-c.back-h.step*.3]:[3.4,0,c.front+h.step*.6];else if(!l)[H,B,et]=S<0?[-3.6,0,1.5]:[3,0,-.4];else{const b0=-p*S,x0=Math.max(0,-u*S)*2.6;[H,B,et]=[3*S,x0,5*b0]}const ft=8.2,Lt=H-2.8*S,dt=B-C,Yt=et-x,W=Math.hypot(Lt,dt,Yt),se=Math.sqrt(Math.max(0,ft*ft-(W/2)**2)),je=b(2.8*S+Lt/2,C+dt/2,x+Yt/2+se*.9,.2);return{id:M,hip:X,knee:je,foot:b(H,B,et)}},tt=L("R",-1),at=L("L",1),nt=tt.foot.near<=at.foot.near?[tt,at]:[at,tt];return{dir:o,sin:a,cos:n,frame:t,anim:r,t:i,phase:y,bob:m,proj:b,head:A,neckY:Et-de+m,neckUp:de-m,torsoHalf:6.5-1.9*Math.abs(a),torsoX:M=>{const S=Math.max(0,Math.min(1,M/(de-Ee)));return pt+(_+(x-_)*S)*a},armR:K,armL:P,handR:K.hand,handL:P.hand,legs:nt,fx:h==null?void 0:h.fx,lying:h!=null&&h.lying?{lift:Math.max(0,-h.bob)}:void 0,flash:r==="hurt"&&i===0}}const z=-.56,mt=-.62,Q=.55,V=-10,_t=-11,Vo=-12,Gt=[-1.03,-.41,.21,.71,1.09];function Zo(o){if(o<=Gt[0])return 0;for(let t=1;t<5;t++)if(o<Gt[t])return t-1+(o-Gt[t-1])/(Gt[t]-Gt[t-1]);return 4}const ta=[0,8,2,10,12,4,14,6,3,11,1,9,15,7,13,5].map(o=>(o+.5)/16);function Kt(o,t){let e=Math.imul(o,374761393)+Math.imul(t,668265263)|0;return e=Math.imul(e^e>>>13,1274126177),((e^e>>>16)>>>0)/4294967295}class ve{constructor(t,e){F(this,"clip",!1);F(this,"grit",.16);F(this,"ax",0);F(this,"ay",0);F(this,"ci",0);F(this,"cj",0);F(this,"dither",!0);F(this,"vgrad",.24);this.L=t,this.S=e}anchor(t,e){this.ax=Math.round(t*this.S),this.ay=Math.round(e*this.S)}noise(){const t=this.ci-this.ax,e=this.cj-this.ay,a=Math.max(2,Math.round(2.6*this.S)),n=Math.floor(t/a),r=Math.floor(e/a),i=t/a-n,s=e/a-r,l=Kt(n,r),c=Kt(n+1,r),f=Kt(n,r+1),h=Kt(n+1,r+1);return((l+(c-l)*i+(f-l)*s+(l-c-f+h)*i*s)*2-1)*.85+(Kt(t+31,e-17)*2-1)*.22}t(t,e=0){const a=this.vgrad*(1-2*this.cj/this.L.h),n=Zo(t+e+a+this.noise()*this.grit)*4;if(!this.dither)return Math.round(n)/4;const r=((this.ci-this.ax)%4+4)%4,i=((this.cj-this.ay)%4+4)%4;return Math.min(4*4,Math.floor(n+ta[i*4+r]))/4}put(t,e,a){const n=this.L;if(t<0||e<0||t>=n.w||e>=n.h)return;const r=n.idx[e*n.w+t]>0;if(a===V){r&&n.reshade(t,e,-1);return}if(a===_t){r&&n.reshade(t,e,1);return}if(a===Vo){n.px(t,e,-1);return}a<0||this.clip&&!r||n.px(t,e,a)}fill(t,e,a,n,r){const{S:i,L:s}=this,l=Math.max(0,Math.floor(t*i)),c=Math.min(s.w-1,Math.ceil(a*i)),f=Math.max(0,Math.floor(e*i)),h=Math.min(s.h-1,Math.ceil(n*i));for(let d=f;d<=h;d++)for(let w=l;w<=c;w++){this.ci=w,this.cj=d;const p=r((w+.5)/i,(d+.5)/i);p!==-1&&this.put(w,d,p)}}ellipse(t,e,a,n,r){this.fill(t-a,e-n,t+a,e+n,(i,s)=>{const l=(i-t)/a,c=(s-e)/n,f=l*l+c*c;return f>1?-1:typeof r=="number"?r:r(l*z+c*mt+Math.sqrt(1-f)*Q,l,c,i,s)})}capsule(t,e,a,n,r,i,s){const l=a-t,c=n-e,f=l*l+c*c||1e-6,h=Math.sqrt(f);let d=-c/h,w=l/h;d+w<0&&(d=-d,w=-w);const p=d*z+w*mt,u=Math.max(r,i);this.fill(Math.min(t,a)-u,Math.min(e,n)-u,Math.max(t,a)+u,Math.max(e,n)+u,(m,y)=>{const g=((m-t)*l+(y-e)*c)/f,_=Math.max(0,Math.min(1,g)),x=r+(i-r)*_,b=m-(t+l*_),A=y-(e+c*_);if(b*b+A*A>x*x)return-1;if(typeof s=="number")return s;const j=Math.max(-1,Math.min(1,(b*d+A*w)/x));return s(j*p+Math.sqrt(1-j*j)*Q,j,g,m,y)})}ribbon(t,e,a){const n=t.length-1;if(n<1)return;const r=[0];for(let x=0;x<n;x++)r.push(r[x]+Math.hypot(t[x+1].x-t[x].x,t[x+1].y-t[x].y));const i=r[n]||1e-6;let s=1/0,l=1/0,c=-1/0,f=-1/0,h=0;for(let x=0;x<=n;x++)s=Math.min(s,t[x].x),c=Math.max(c,t[x].x),l=Math.min(l,t[x].y),f=Math.max(f,t[x].y),h=Math.max(h,e(r[x]/i));h=Math.max(h,e(.5))*1.15;const d=new Float64Array(n),w=new Float64Array(n),p=new Float64Array(n),u=new Float64Array(n),m=new Float64Array(n),y=new Float64Array(n),g=new Float64Array(n),_=new Float64Array(n);for(let x=0;x<n;x++){const b=t[x],A=t[x+1],j=A.x-b.x,I=A.y-b.y,T=j*j+I*I||1e-6,K=Math.sqrt(T);let P=-I/K,L=j/K;P+L<0&&(P=-P,L=-L),d[x]=b.x,w[x]=b.y,p[x]=j,u[x]=I,m[x]=T,y[x]=K,g[x]=P,_[x]=L}this.fill(s-h,l-h,c+h,f+h,(x,b)=>{let A=1/0,j=0,I=0,T=0;for(let L=0;L<n;L++){const tt=d[L],at=w[L],nt=p[L],R=u[L],E=Math.max(0,Math.min(1,((x-tt)*nt+(b-at)*R)/m[L])),U=x-(tt+nt*E),ht=b-(at+R*E),M=U*U+ht*ht;if(M>=A)continue;A=M;const S=g[L],C=_[L];j=(r[L]+y[L]*E)/i,I=U*S+ht*C,T=S*z+C*mt}const K=e(j);if(K<=0||A>K*K)return-1;const P=Math.max(-1,Math.min(1,I/K));return a(P*T+Math.sqrt(1-P*P)*Q,P,j,x,b)})}axis(t,e,a,n,r,i,s,l){let c=-n,f=a;c+f<0&&(c=-c,f=-f);const h=[t+a*r,t+a*i],d=[e+n*r,e+n*i];this.fill(Math.min(...h)-s,Math.min(...d)-s,Math.max(...h)+s,Math.max(...d)+s,(w,p)=>{const u=(w-t)*a+(p-e)*n,m=(w-t)*c+(p-e)*f;return u<r||u>i||Math.abs(m)>s?-1:l(u,m)})}tri(t,e,a,n){const r=(i,s,l,c)=>(l-s.x)*(i.y-s.y)-(i.x-s.x)*(c-s.y);this.fill(Math.min(t.x,e.x,a.x),Math.min(t.y,e.y,a.y),Math.max(t.x,e.x,a.x),Math.max(t.y,e.y,a.y),(i,s)=>{const l=r(t,e,i,s),c=r(e,a,i,s),f=r(a,t,i,s),h=l<0||c<0||f<0,d=l>0||c>0||f>0;return h&&d?-1:typeof n=="number"?n:n(i,s)})}rect(t,e,a,n,r){this.fill(t,e,t+a,e+n,(i,s)=>i<t||i>t+a||s<e||s>e+n?-1:typeof r=="number"?r:r(i,s))}line(t,e,a,n,r){const i=this.S;let s=Math.floor(t*i),l=Math.floor(e*i);const c=Math.floor(a*i),f=Math.floor(n*i),h=Math.abs(c-s),d=-Math.abs(f-l),w=s<c?1:-1,p=l<f?1:-1;let u=h+d;for(;this.put(s,l,r),!(s===c&&l===f);){const m=2*u;m>=d&&(u+=d,s+=w),m<=h&&(u+=h,l+=p)}}cells(t,e,a,n=Math.max(1,Math.round(this.S))){const r=Math.floor(e*this.S),i=Math.floor(a*this.S);t.forEach((s,l)=>{for(let c=0;c<s.length;c++){const f=s.charCodeAt(c)-48;if(!(f<0||f>4))for(let h=0;h<n;h++)for(let d=0;d<n;d++)this.put(r+c*n+d,i+l*n+h,f)}})}cellsPx(t,e,a,n=Math.max(1,Math.round(this.S))){this.cells(t,(e+.01)/this.S,(a+.01)/this.S,n)}dot(t,e,a){this.put(Math.floor(t*this.S),Math.floor(e*this.S),a)}fold(t,e,a,n,r=!0){const i=this.clip;if(this.clip=!0,this.line(t,e,a,n,V),r){const s=1/this.S;this.line(t-s,e-s,a-s,n-s,_t)}this.clip=i}}function Ge(o,t){var a;const e=o.find(n=>n.slot===t);return e?(a=e.item.hold)!=null?a:"up":void 0}let Pt;function ea(){if((Pt==null?void 0:Pt.S)===$)return Pt.taps;const o=Math.max(2,Math.round(2.8*$)),t=[];for(let e=0;e<=o;e++)for(let a=0;a<=o;a++){if(!a&&!e)continue;const n=Math.hypot(a*.8,e);n>o||t.push([a,e,.85*(1-(n-1)/o)])}return Pt={S:$,taps:t},t}const oa=.75,aa=["body","face","bottom","shoes","top","bag","scarf","hair","weapon_off","weapon_main"];let q=new qt(G,Y),st=new ve(q,$);function na(o,t){var n;const e=(n=o.anchor)!=null?n:"torso";if(typeof e=="function")return e(t);const a=t.pose;switch(e){case"head":return a.head;case"hip":return{x:(a.legs[0].hip.x+a.legs[1].hip.x)/2,y:a.legs[0].hip.y};case"hand_R":return a.handR;case"hand_L":return a.handL;default:return{x:a.proj(0,0,0).x,y:a.neckY}}}function me(o,t,e,a,n={}){var c,f,h,d,w,p,u,m,y;const r=(c=n.phase)!=null?c:e%4;(q.w!==G||st.S!==$)&&(q=new qt(G,Y),st=new ve(q,$));const i=vt(t,e,{armedR:Ge(o,"weapon_main"),armedL:Ge(o,"weapon_off")}),s=[],l=(h=(f=o.find(g=>g.slot==="body"))==null?void 0:f.palettes)!=null?h:{};o.forEach((g,_)=>{var j,I;const x=g.slot==="weapon_main"?g.item.hold==="bow"?i.handL:i.handR:g.slot==="weapon_off"?i.handL:void 0,b=(I=(j=g.item).layerOverride)==null?void 0:I.call(j,t,e),A=Object.values(g.palettes)[0];g.item.parts.forEach((T,K)=>{var nt;if(T.glow&&n.glow===!1)return;const P={dir:t,frame:e,anim:i.anim,pose:i,L:q,g:st,hand:x,phase:r,pal:(R="main")=>{var E,U;q.use((U=(E=g.palettes[R])!=null?E:l[R])!=null?U:A)}};let L;T.layer==="weapon"?L=x&&!x.weaponFront?"weapon_back":x!=null&&x.weaponMid?"weapon_mid":"weapon_front":typeof T.layer=="function"?L=T.layer(P):L=T.layer;const tt=(nt=b==null?void 0:b[L])!=null?nt:Le[L],at=aa.indexOf(g.slot)*1e3+_*50+K;s.push({z:tt,order:at,part:T,ctx:P})})}),s.sort((g,_)=>g.z-_.z||g.order-_.order);for(const{part:g,ctx:_}of s){if(q.clear(),st.clip=!1,st.grit=.16,st.dither=!0,st.anchor(pt,i.neckY),g.frames){const x=g.frames[t];if(x){_.pal(g.paletteKey);const b=na(g,_);st.cells(x,b.x+((w=(d=g.offset)==null?void 0:d[0])!=null?w:0),b.y+((u=(p=g.offset)==null?void 0:p[1])!=null?u:0))}}if((m=g.draw)==null||m.call(g,_),g.mask==="below"){q.drawOnto(a,0,0,void 0,!0);continue}g.outline!==!1&&!g.glow&&(q.bounce(),q.outline(),a.castShadow(q,ea())),q.drawOnto(a,0,0,g.glow?void 0:(y=g.innerLine)!=null?y:oa),g.innerLine!==void 0&&a.fillInteriorOutlines(g.innerLine,q.palettes)}i.lying&&ia(a,i.lying.lift),i.flash&&ra(a)}function ra(o){const t=N(0),e=N(5),a=N(4);for(let n=0;n<o.idx.length;n++){const r=o.idx[n];!r||r===t||(o.idx[n]=r===e?N(3):a)}}function ia(o,t){const{w:e,h:a}=o,n=o.idx.slice(),r=o.pid.slice();let i=e,s=a,l=-1,c=-1;for(let p=0;p<a;p++)for(let u=0;u<e;u++)n[p*e+u]&&(u<i&&(i=u),u>l&&(l=u),p<s&&(s=p),p>c&&(c=p));if(l<0)return;const f=c-s+1,h=l-i+1;let d=Math.round(pt*$-f/2);d+f>e&&(d=e-f);const w=Math.round(Et*$-t*$)-h;o.idx.fill(0);for(let p=s;p<=c;p++)for(let u=i;u<=l;u++){const m=n[p*e+u];if(!m)continue;const y=d+(c-p),g=w+(u-i);y<0||g<0||y>=e||g>=a||(o.idx[g*e+y]=m,o.pid[g*e+y]=r[p*e+u])}}const Ke=["face","hair","top","bottom","shoes","scarf","bag","weapon_main","weapon_off"];class sa{constructor(t){F(this,"slots",new Map);F(this,"bodyOverrides",{});this.body=t}equip(t,e){this.slots.set(t,{item:e,overrides:{}})}unequip(t){this.slots.delete(t)}get(t){var e;return(e=this.slots.get(t))==null?void 0:e.item}variantOf(t){var e;return(e=this.slots.get(t))==null?void 0:e.variantId}setPalette(t,e,a="main"){const n=this.slots.get(t);n&&(n.overrides[a]=e,n.variantId=void 0)}setBodyPalette(t,e="skin"){this.bodyOverrides[e]=t}setVariant(t,e){var r;const a=this.slots.get(t),n=(r=a==null?void 0:a.item.variants)==null?void 0:r.find(i=>i.id===e);a&&n&&(a.overrides={...n.palettes},a.variantId=n.id)}resolve(){var a;const t=new Set;for(const n of this.slots.values())(a=n.item.hides)==null||a.forEach(r=>t.add(r));const e=[{slot:"body",item:this.body,palettes:{...this.body.palettes,...this.bodyOverrides}}];for(const n of Ke){const r=this.slots.get(n);!r||t.has(n)||e.push({slot:n,item:r.item,palettes:{...r.item.palettes,...r.overrides}})}return e}}function ut(o,t){return Math.abs(o.pose.sin)>.5&&t.near<0?-.6:0}function wt(o,t){return t==="R"?o.pose.armR:o.pose.armL}const ue=o=>t=>wt(t,o).hand.front?"arm_front":"arm_back";function Pe(o,t,e,a=1,n=0){const{g:r}=o,i=wt(o,t),s=ut(o,i.hand)+n,l=i.elbow.x+(i.hand.x-i.elbow.x)*a,c=i.elbow.y+(i.hand.y-i.elbow.y)*a;return r.anchor(i.elbow.x,i.elbow.y),r.capsule(i.shoulder.x,i.shoulder.y,i.elbow.x,i.elbow.y,e[0],e[1],f=>r.t(f,s)),r.capsule(i.elbow.x,i.elbow.y,l,c,e[1],e[1]+(e[2]-e[1])*a,f=>r.t(f,s)),{x:l,y:c}}function J(o,t,e,a){var f,h;const{g:n,pose:r}=o,i=r.neckY,s=(f=e.flare)!=null?f:1,l=r.torsoHalf+((h=e.pad)!=null?h:0),c=Math.abs(r.torsoX(0)-r.torsoX(t));n.fill(pt-l-s-1-c,i,pt+l+s+1+c,i+t,(d,w)=>{const p=w-i;if(p<0||p>t)return-1;let u=l;p<2.4&&(u-=(2.4-p)*(2.4-p)*.35),p>t-7&&(u+=s*(p-(t-7))/7);const m=(d-r.torsoX(p))/u;return Math.abs(m)>1?-1:a(m*z+Math.sqrt(1-m*m)*Q+.05,m,p,d,w)})}function gt(o){return o.pose.torsoX(5)+o.pose.torsoHalf*.72*o.pose.sin}function Mt(o){const t=e=>({layer:ue(e),draw:a=>{var f,h;const{g:n}=a,r=wt(a,e),i=ut(a,r.hand),s=(f=o.r)!=null?f:2,l=(h=o.length)!=null?h:.72;a.pal(o.key),n.anchor(r.elbow.x,r.elbow.y),n.ellipse(r.shoulder.x,r.shoulder.y+.4,s+.5,s+.3,d=>n.t(d,i));const c=Pe(a,e,[s,s-.1,s+.25],l);if(n.fold(r.elbow.x-1.5,r.elbow.y-.3,r.elbow.x+1.6,r.elbow.y+.5),o.cuffKey){a.pal(o.cuffKey);const d=(l-.2)/l,w=r.elbow.x+(c.x-r.elbow.x)*d,p=r.elbow.y+(c.y-r.elbow.y)*d;n.capsule(w,p,c.x,c.y,s+.15,s+.3,(u,m,y)=>y>1?-1:n.t(u,i+.1))}}});return[t("L"),t("R")]}const Ue=k("skin","#4a2620","#a86450","#dc9e7c","#f4caa2","#fff0d6"),we={fair:Ue,light:k("skin-light","#54302a","#bc7c66","#eab896","#fadcbe","#fff4e4"),tan:k("skin-tan","#3a1e14","#8a4e34","#c07a52","#e0a476","#f6d0a8"),deep:k("skin-deep","#24120c","#5a3020","#8a5236","#b47a54","#dcaa82")};function De(o){return{layer:ue(o),draw:t=>{const{g:e}=t,a=wt(t,o),n=ut(t,a.hand);e.grit=.08,t.pal("skin"),Pe(t,o,[1.6,1.45,1.3]),e.ellipse(a.hand.x,a.hand.y+.7,1.7,1.8,r=>e.t(r,n-.05))}}}function la(o){const{g:t,pose:e,dir:a}=o,n=e.head.x+e.sin*.9,r=e.head.y;t.grit=.07,t.anchor(n,r),o.pal("skin"),t.fill(n-xt-1,r-kt-1,n+xt+1,r+kt+1,(i,s)=>{const l=i-n,c=s-r,f=c>0,h=f?xt*(1.05-.05*(c/kt)*(c/kt)):xt,d=f?kt*.84:kt,w=l/h,p=c/d;if((f?Math.abs(w)**2+Math.abs(p)**2.3:w*w+p*p)>1)return-1;const m=Math.min(1,w*w+p*p),y=w*z+p*mt+Math.sqrt(1-m)*Q;return c<-3.4?1:Math.max(1,Math.min(3,t.t(y*.62,.2)))}),t.clip=!0,a==="E"?(o.pal("skin"),t.dot(n+xt-1.4,r+4.4,1),t.ellipse(n-.8,r+2.6,1.6,2.2,i=>i>.3?2:1),t.dot(n-.8,r+2.6,1)):a==="NE"&&t.ellipse(n+6.8,r+2.6,1.3,2.1,i=>i>.3?2:1),t.clip=!1}function ca(o){const{g:t,pose:e}=o,a=e.head.y,n=e.head.x-e.sin*.6,r=e.torsoX(0),i=a+7,s=e.neckY+2;t.fill(Math.min(n,r)-2.2,i,Math.max(n,r)+2.2,s,(l,c)=>{const f=(c-i)/Math.max(.1,s-i),h=n+(r-n)*f;return Math.abs(l-h)>1.9?-1:c<a+10.4?0:1})}const ha={id:"body",name:"身体",slot:"top",palettes:{skin:Ue},parts:[De("L"),De("R"),{layer:"legs",draw:o=>{const{g:t}=o;t.grit=.08,o.pal("skin");for(const e of o.pose.legs){const a=ut(o,e.foot);t.capsule(e.hip.x,e.hip.y,e.knee.x,e.knee.y,2,1.7,n=>t.t(n,a)),t.capsule(e.knee.x,e.knee.y,e.foot.x,e.foot.y-1.5,1.7,1.5,n=>t.t(n,a))}}},{layer:"torso",draw:o=>{o.g.grit=.08,o.pal("skin"),ca(o),J(o,12.5,{flare:0,pad:-.3},t=>o.g.t(t))}},{layer:"head",draw:la}]},Xe=k("satchel-leather","#1e1008","#583216","#8e5828","#bc8442","#eabc64"),fa=k("satchel-brass","#3e2408","#8a5c16","#d8a430","#f6d86c","#fff6c0"),ge=o=>o.pose.proj(-4,o.pose.neckUp-12.6,2.4,.1),Ye=o=>o.dir==="N"?"cape":"bag",Zt=["43","31"],da={id:"bag_satchel",name:"棕色皮挎包",slot:"bag",palettes:{main:Xe,metal:fa},variants:[{id:"leather",name:"棕皮",palettes:{main:Xe}},{id:"olive",name:"橄榄帆布",palettes:{main:v("satchel-olive","#70703a")}}],parts:[{layer:"bag",draw:o=>{const{g:t,pose:e}=o,a=e.proj(5.4,e.neckUp+.4,0,0),n=ge(o);o.pal("main"),t.capsule(a.x,a.y,n.x,n.y-3,.8,.8,(r,i)=>i<-.2?3:i>.45?0:1)}},{layer:Ye,draw:o=>{const{g:t}=o,e=ge(o),a=3.9-Math.abs(o.pose.sin)*.9,n=3.7;o.pal("main"),t.anchor(e.x,e.y),t.grit=.24,t.fill(e.x-a,e.y-n,e.x+a,e.y+n,(r,i)=>{const s=(r-e.x)/a,l=(i-e.y)/n;if(s**4+l**4>1)return-1;const c=s*z+Math.sqrt(1-s*s)*Q,f=-.05+.3*Math.cos(s*1.4);return l<f?l>f-.2?1:t.t(c,.3):t.t(c,-.3)}),t.clip=!0,t.line(e.x-a+.8,e.y+n-.7,e.x+a-.8,e.y+n-.7,V),t.clip=!1}},{layer:Ye,anchor:ge,offset:[-1,0],paletteKey:"metal",outline:!1,frames:{S:Zt,SE:Zt,E:Zt,NE:Zt}}]},pa=Object.freeze(Object.defineProperty({__proto__:null,satchel:da},Symbol.toStringTag,{value:"Module"})),Ce=k("trousers-dark","#0a0a12","#1a1c2a","#2e3142","#484c62","#6c7088"),qe=o=>({layer:"bottom",draw:t=>{const{g:e}=t,a=t.pose.legs[o],n=ut(t,a.foot),r=a.foot.x,i=a.foot.y-5;t.pal("main"),e.anchor(r,i),e.capsule(a.hip.x,a.hip.y,a.knee.x,a.knee.y,2.5,2.1,c=>e.t(c,n+.05)),e.capsule(a.knee.x,a.knee.y,r,i,2.1,1.95,c=>e.t(c,n+.05));const s=a.knee.x,l=a.knee.y;e.fold(s-1.8,l,s+1.4,l+.7),e.fold(r-1.8,i-1.4,r+1.6,i-.8,!1)}}),ma={id:"bottom_trousers",name:"深色长裤",slot:"bottom",palettes:{main:Ce},variants:[{id:"dark",name:"深灰蓝",palettes:{main:Ce}},{id:"brown",name:"深棕",palettes:{main:v("trousers-brown","#54392a")}},{id:"white",name:"米白",palettes:{main:v("trousers-cream","#c4b898")}}],parts:[qe(0),qe(1),{layer:"bottom",draw:o=>{const{g:t,pose:e}=o,a=e.torsoHalf-.2,n=e.legs[0].hip.y,r=(e.legs[0].hip.x+e.legs[1].hip.x)/2;if(o.pal("main"),t.fill(r-a,n-4.5,r+a,n+3,(i,s)=>{const l=(i-r)/a;return Math.abs(l)>1||s<n-4.5||s>n+1+1.4*(1-Math.abs(l))?-1:t.t(l*z+Math.sqrt(1-l*l)*Q,-.15)}),Math.abs(e.sin)<.9){const i=r+e.sin*2.2;t.clip=!0,t.line(i,n-1,i,n+2.2,V),t.clip=!1}}}]},ua=Object.freeze(Object.defineProperty({__proto__:null,trousers:ma},Symbol.toStringTag,{value:"Module"}));function We(o){return o.map(t=>[...t].reverse().join(""))}function ze(o){const t=o.g.S,e=o.pose.head.x+o.pose.sin*.9,a=o.pose.head.y;return{px:Math.round(e*t),py:Math.round((a+.4)*t),k:Math.max(1,Math.round(t))}}function wa(o,t){var l,c,f,h;const e=t.views[o.dir];if(!e)return;const{g:a}=o,{px:n,py:r,k:i}=ze(o),s=(d,w)=>a.cellsPx([String(w)],n+d[0]*i,r+d[1]*i);o.pal("eye");for(const[d,w,p]of(l=e.eyes)!=null?l:[]){const u=d.endsWith("!"),m=t.patterns[u?d.slice(0,-1):d];if(!m)throw new Error(`${t.id}: unknown eye pattern ${d}`);a.cellsPx(u?We(m):m,n+w*i,r+p*i)}o.pal("blush");for(const d of(c=e.blush)!=null?c:[])s(d,2);o.pal("skin");for(const d of(f=e.mouth)!=null?f:[])s(d,1);for(const d of(h=e.brows)!=null?h:[])s(d,1)}function Je(o){var a;const t={eye:k(`${o.id}-eye`,...o.palettes.eye),blush:k(`${o.id}-blush`,...o.palettes.blush)},e=((a=o.variants)!=null?a:[]).map(n=>{const r={};return n.palettes.eye&&(r.eye=k(`${o.id}-${n.id}-eye`,...n.palettes.eye)),n.palettes.blush&&(r.blush=k(`${o.id}-${n.id}-blush`,...n.palettes.blush)),{id:n.id,name:n.name,palettes:r}});return{id:o.id,name:o.name,slot:"face",palettes:t,variants:e,parts:[{layer:"head",mask:"below",outline:!1,draw:n=>wa(n,o)}]}}const ga=Object.freeze(Object.defineProperty({__proto__:null,faceOrigin:ze,makeFace:Je,mirrorPattern:We},Symbol.toStringTag,{value:"Module"}));function lt(o){const t=o.hand;if(t)return{x:t.x,y:t.y+.6,dx:Math.cos(t.angle),dy:Math.sin(t.angle),k:t.reach}}function Z(o,t,e,a,n,r){o.g.axis(t.x,t.y,t.dx,t.dy,e*t.k,a*t.k,n,(i,s)=>r(i/t.k,s))}function O(o,t,e=0){return{x:o.x+o.dx*t*o.k-o.dy*e,y:o.y+o.dy*t*o.k+o.dx*e}}function ye(o,t,e,a){const{g:n}=o;n.fill(t-a,e-a,t+a,e+a,(r,i)=>{const s=Math.abs(r-t),l=Math.abs(i-e),c=Math.min(s,l);return s+l>a||c>Math.max(.5,a*.18)?s*s+l*l<(a*.32)**2?3:-1:s+l<a*.45?4:3})}function jt(o,t,e="fx"){return{layer:"weapon_front",outline:!1,draw:a=>{const n=a.hand,r=lt(a);if(!n||!r||n.trailFrom===void 0)return;let s=n.angle-n.trailFrom;for(;s>Math.PI;)s-=2*Math.PI;for(;s<-Math.PI;)s+=2*Math.PI;if(Math.abs(s)<.2)return;const l=o*r.k,c=t*r.k;a.pal(e),a.g.grit=0,a.g.dither=!1,a.g.fill(r.x-c,r.y-c,r.x+c,r.y+c,(f,h)=>{const d=f-r.x,w=h-r.y,p=Math.hypot(d,w);if(p<l||p>c)return-1;let u=Math.atan2(w,d)-n.trailFrom;for(;u>Math.PI;)u-=2*Math.PI;for(;u<-Math.PI;)u+=2*Math.PI;const m=u/s;if(m<0||m>.92)return-1;const y=(p-l)/(c-l);return y<1-m*1.1?-1:m>.6&&y>.55?4:m>.3?3:2}),a.g.dither=!0}}}function At(o,t="fx",e=1){return{layer:"weapon_front",outline:!1,draw:a=>{const n=lt(a),r=a.pose.fx;if(!n||r!=="glow"&&r!=="burst")return;const i=o(n);if(a.pal(t),a.g.grit=0,r==="glow")ye(a,i.x,i.y,3.2*e),a.g.dot(i.x-4*e,i.y+2.5*e,3),a.g.dot(i.x+3.5*e,i.y-3.2*e,4);else{ye(a,i.x,i.y,6*e);for(const[s,l]of[[-5.5,-3.5],[5,3],[3,-5.5],[-4,4.5]])a.g.dot(i.x+s*e,i.y+l*e,4)}}}}function St(o,t,e=!1){var c;const a=lt(o);if(!a)return;const n=t.to;o.pal("blade"),Z(o,a,t.from,t.to,t.half+Math.abs((c=t.curve)!=null?c:0)+.4,(f,h)=>{var m;const d=(f-t.from)/(n-t.from),w=((m=t.curve)!=null?m:0)*d*d,p=f<n-t.tip?t.half:t.half*(n-f)/t.tip,u=h-w;return Math.abs(u)>p?-1:t.core==="glow"&&Math.abs(u)<p*.35&&f>t.from+1?4:t.core==="fuller"&&Math.abs(u)<.35&&f>t.from+1.5&&f<n-t.tip-1?1:u<-p*.15?f>t.from+(n-t.from)*.3&&f<n-t.tip?4:3:u>p*.5?1:2}),o.pal("grip"),Z(o,a,-t.grip,t.from-.6,.8,(f,h)=>h>.3?1:Math.floor(f*1.2+10)%2?2:3),o.pal("hilt");const[r,i,s]=t.guard;Z(o,a,t.from-1.6,t.from+.4,r,(f,h)=>{const d=s*Math.abs(h)/r;return f<t.from-1.4+d-i/2||f>t.from-1.4+d+i/2?-1:h<-r*.5?4:h>r*.55?1:3});const l=O(a,-t.grip-t.pommel*.6);if(o.g.ellipse(l.x,l.y,t.pommel,t.pommel,f=>f>.4?4:f>-.2?2:1),e){o.pal("gem");const f=O(a,t.from-1.2);o.g.ellipse(f.x,f.y,1.1,1.1,h=>h>.3?4:3)}}const ya=Object.freeze(Object.defineProperty({__proto__:null,along:Z,at:O,drawSword:St,frameOf:lt,fxPart:At,sparkle:ye,trailPart:jt},Symbol.toStringTag,{value:"Module"}));function be(o,t,e,a,n=.4,r=1.15){o.g.grit=0,o.g.fill(t-r-.6,e-a-.6,t+r+.6,e+.6,(i,s)=>{const l=(e-s)/a;if(l<-.4||l>1)return-1;const c=r*(1-Math.max(0,l))+.12;return Math.abs(i-t-l*n)>c?-1:l>.55?4:l>.1?3:2})}function Qe(o,t,e,a,n,r){o.g.grit=0;for(let i=0;i<a;i++){const s=r+i*Math.PI*2/a,l=i%2?n*.6:n;for(let c=3.4;c<l;c+=.6)o.g.dot(t+Math.cos(s)*c,e+Math.sin(s)*c*.9,c<l*.55?4:3)}}function te(o,t,e,a){o.g.dot(t,e,4);for(let n=1;n<=a;n++)for(const[r,i]of[[1,0],[-1,0],[0,1],[0,-1]])o.g.dot(t+r*n*.8,e+i*n*.8,n===a?3:4)}function Ut(o,t="fx"){return{layer:"weapon",glow:!0,outline:!1,draw:e=>{const a=lt(e);a&&(e.pal(t),o(e,a))}}}const Ve=Ut((o,t)=>{const e=O(t,37.5);Qe(o,e.x,e.y,8,9.5+o.phase%2*2,o.phase*Math.PI/16),(o.phase===1||o.phase===3)&&te(o,e.x,e.y,1)}),Ze=Ut((o,t)=>{for(let e=0;e<4;e++){const a=9+e*5+(o.phase*3+e*2)%4*.5,n=1.6+(o.phase+e)%3*.8,r=O(t,a,-2.6-e%2*.6);be(o,r.x,r.y,n)}}),to=Ut((o,t)=>{[O(t,15,-3.4),O(t,9,3.2),O(t,19,2.6),O(t,5.5,-2.8)].forEach((a,n)=>n===o.phase?te(o,a.x,a.y,2):o.g.dot(a.x,a.y,(n+o.phase)%2?3:2))}),eo=Ut((o,t)=>{if(o.phase!==0)return;const e=O(t,3);te(o,e.x,e.y,1)},"gem");function xe(o,t="top"){return{layer:t,glow:!0,outline:!1,draw:o}}const oo=xe(o=>{const{pose:t}=o;if(o.pal("rune"),o.g.grit=0,t.cos>.3){const e=t.torsoX(5),a=t.neckY+9.6-o.phase*1.7;for(let n=0;n<3;n++)o.g.dot(e,a+n*.7,n===0?4:3);o.g.dot(e-.7,a,3),o.g.dot(e+.7,a,3)}for(const e of["L","R"]){const a=wt(o,e),n=o.phase%2===0==(e==="L");!a.hand.front&&Math.abs(t.cos)<.3||(o.g.dot(a.shoulder.x,a.shoulder.y+.2,n?4:3),n&&o.g.dot(a.shoulder.x+(e==="L"?1:-1)*t.cos,a.shoulder.y-2.2-(o.phase>>1)*1.6,4))}},"arm_front"),ao=xe(o=>{const{pose:t}=o;if(t.cos<=.3)return;o.pal("gem");const e=t.torsoX(5),a=t.neckY+5.4,n=4+o.phase%2*2.5;o.g.grit=0;for(let r=3.6;r<n+3;r+=.7)for(const[i,s]of[[1,0],[-1,0],[0,1],[0,-1]])o.g.dot(e+i*r,a+s*r,r<5?4:3)}),no=["L","R"].map(o=>xe(t=>{const e=wt(t,o);t.pal("fx");const a=4.2+(t.phase+(o==="L"?0:2))%4*1.1,n=(o==="L"?1:-1)*t.pose.cos*2.6;!e.hand.front&&Math.abs(t.pose.cos)<.3||be(t,e.shoulder.x+n,e.shoulder.y-2,a,.25,1.7)},"weapon_front")),ba=Object.freeze(Object.defineProperty({__proto__:null,bladeStars:to,crestBurst:ao,fangFlames:Ze,flame:be,pauldronFlames:no,rays:Qe,rubyGlint:eo,runeFlow:oo,scepterRays:Ve,twinkle:te,weaponGlow:Ut},Symbol.toStringTag,{value:"Module"})),ee=xt/10.4,yt=11.6*ee,It=11*ee,ro=10.2*ee,ke=18*Math.PI/180,io=Math.cos(ke),so=Math.sin(ke),oe=Math.PI/180;function xa(o,t,e,a,n,r){const i=a*oe,s=n*oe,l=Math.cos(i),c=Math.sin(i)*Math.cos(s),f=Math.sin(i)*Math.sin(s),h=c*ro/yt,d=f*o.cos+h*o.sin,w=h*o.cos-f*o.sin;return{x:t+yt*r*d,y:e-It*r*(l*io-w*so),near:w*io+l*so}}function ka(o,t,e,a,n){const r=[],s=o.anim==="walk"?Math.sin(o.phase*2+n*1.3):0;for(let l=0;l<=12;l++){const c=l/12,f=1+a.lift+(a.flick-1+s*.03)*c*c*c;r.push(xa(o,t,e,a.a0+(a.a1-a.a0+s*2.5)*c,a.phi+(a.twist+s*4)*c*c,f))}if(a.drop>0){const l=r[12],c=Math.abs(l.x-t)<.5?0:Math.sign(l.x-t),f=8;for(let h=1;h<=f;h++){const d=h/f;r.push({x:l.x+a.spread*c*d*d+s*.9*d*d,y:l.y+a.drop*d,near:l.near})}}return r}function _a(o,t=.55,e=1.7){return o<t?.5+.5*Math.min(1,o/.55):Math.max(0,1-Math.pow((o-t)/(1-t),e))}function lo(o,t){for(let e=0;e<o.length-1;e++){const[a,n]=o[e],[r,i]=o[e+1];if(t<r)return r===a?i:n+(t-a)/(r-a)*(i-n)}return o[o.length-1][1]}function _e(o,t,e,a,n){const r=a!=="front",{g:i,pose:s}=o,l=s.head.x+s.sin*.2,c=s.head.y-1.2;o.pal("main"),i.grit=n.grit,i.dither=n.dither,i.anchor(l,c);const f=(w,p)=>-((w-l)/yt)*.62+(c-p)/It*.7,h=(w,p)=>{const u=(w-l)/yt,m=(c-p)/It-.16*u*u;return m>.3&&m<.46&&f(w,p)>.12};if(a==="front"){const w=Math.hypot(yt*s.cos,ro*s.sin);i.fill(l-yt,c-It,l+yt,c+It,(p,u)=>{const m=(p-l)/w,y=(c-u)/It,g=1-m*m;if(g<=0||y*y>g)return-1;const _=Math.sqrt(g),x=Math.acos(Math.max(-1,Math.min(1,y/_)))-ke,b=_*Math.cos(x),A=_*Math.sin(x),j=m*s.cos-A*s.sin,I=m*s.sin+A*s.cos,T=Math.acos(Math.max(-1,Math.min(1,b)))/oe,K=Math.abs(Math.atan2(j,I))/oe;return T>=lo(e,K)?-1:h(p,u)&&n.ring?3:Math.max(n.floor,i.t(f(p,u)*.9-.55))})}const d=t.map((w,p)=>{const u=ka(s,l,c,w,p);return{k:w,pts:u,depth:u[8].near+w.tier*.6}}).filter(w=>{const p=w.pts[8].near<-.12;return a==="front"?!p:p&&a==="behind"==w.k.drop>0}).sort((w,p)=>w.depth-p.depth);for(const{k:w,pts:p}of d)i.ribbon(p,u=>w.width*ee*_a(u,w.taper,w.tip),(u,m,y,g,_)=>{if(w.tier===2)return m>.2?1:y>.5?3:2;const x=f(g,_);let b=i.t(x*n.global+u*n.clump-.22+(r?-.45:0));return n.ring&&h(g,_)&&m<.6&&(b=x>.42?4:Math.max(b+1,3+.5)),n.streaks&&a==="front"&&m>-.75&&m<-.2&&y>.08&&y<.7&&x>-.3&&(b=x>.25&&y>.15&&y<.45?4:Math.max(b+1,3)),m>.72&&y>.25&&(b=Math.max(n.seamFloor,b-1.5)),b=Math.min(4,Math.max(n.floor,b)),y>.9&&(b=Math.max(1,b-.5)),b})}function co(o,t){if(t.palette)return k(o,...t.palette);if(t.base)return v(o,t.base);throw new Error(`variant ${o}: needs palette or base`)}function ho(o,t=[]){var s,l,c,f;const e=o.locks.map(h=>({a0:5,twist:0,flick:1.06,lift:0,tier:0,tip:1.7,taper:.55,drop:0,spread:0,...h})),a={clump:.3,global:.95,ring:!0,streaks:!1,grit:.1,dither:!0,closeHoles:!1,seamFloor:0+.5,floor:0,...o.style},n=(s=o.variants)!=null?s:[],i=[...n,...t.filter(h=>!n.some(d=>d.id===h.id))].map(h=>({id:h.id,name:h.name,palettes:{main:co(`${o.id}-${h.id}`,h)}}));return{id:o.id,name:o.name,slot:"hair",palettes:{main:k(`${o.id}-main`,...o.palette)},variants:i,parts:[{layer:"cape",innerLine:(l=o.style)==null?void 0:l.innerLine,draw:h=>{_e(h,e,o.hairline,"behind",a),a.closeHoles&&h.L.closeHoles(a.seamFloor)}},{layer:"hair_back",innerLine:(c=o.style)==null?void 0:c.innerLine,draw:h=>{_e(h,e,o.hairline,"back",a),a.closeHoles&&h.L.closeHoles(a.seamFloor)}},{layer:"hair",innerLine:(f=o.style)==null?void 0:f.innerLine,draw:h=>{_e(h,e,o.hairline,"front",a),a.closeHoles&&h.L.closeHoles(a.seamFloor)}}]}}const Ma=Object.freeze(Object.defineProperty({__proto__:null,hairlineAt:lo,makeHair:ho,variantPalette:co},Symbol.toStringTag,{value:"Module"})),fo=k("scarf-navy","#05081a","#111c44","#22346e","#3c549c","#7c94d4"),ja={id:"scarf_navy",name:"深蓝围巾",slot:"scarf",palettes:{main:fo},variants:[{id:"navy",name:"深蓝",palettes:{main:fo}},{id:"crimson",name:"绯红",palettes:{main:v("scarf-crimson","#a82838")}},{id:"cream",name:"米白",palettes:{main:v("scarf-cream","#d8ccac")}},{id:"moss",name:"苔绿",palettes:{main:v("scarf-moss","#527e38")}}],tail:{anchor:o=>o.proj(2.4,o.neckUp-.5,-5.2),paletteKey:"main",segments:7,segmentLength:2.7},parts:[{layer:"scarf",draw:o=>{const{g:t,pose:e}=o,a=e.torsoHalf+2.2-1.5*Math.abs(e.sin),n=e.torsoX(0)+e.sin*.5,r=e.neckY+2.1,i=2.6;if(o.pal("main"),t.grit=.26,t.fill(n-a,r-i,n+a,r+i,(s,l)=>{const c=(s-n)/a,f=(l-r)/i;if(Math.abs(c)**2.6+Math.abs(f)**3>1)return-1;const h=f*mt*1.2+c*z*.6+Math.sqrt(Math.max(0,1-f*f))*Q*.9;return t.t(h+Math.sin((s+l*.6)*1.7)*.32,-.02)}),t.fold(n-a+1,r-1.2,n+a-1.6,r+1,!1),e.cos>.3){const s=e.torsoX(0)+(a-3.8)*(.3+e.sin*.6);t.capsule(s+.2,r+2.8,s+.8,r+9.4,1.5,1.8,(l,c,f)=>f>.68&&f<.78||f>.88&&f<.97?l>.2?4:3:t.t(l)),t.ellipse(s,r+2.2,2.1,2,l=>t.t(l,.08))}else if(e.cos<-.3){const s=e.proj(2.4,e.neckUp-.5,-5.2);t.ellipse(s.x,s.y+.6,2.1,1.9,l=>t.t(l,.08))}}}]},Aa=Object.freeze(Object.defineProperty({__proto__:null,navyScarf:ja},Symbol.toStringTag,{value:"Module"})),po=k("boots-brown","#160c06","#3c2212","#6c4024","#9c6838","#d09c5c"),mo=o=>({layer:"shoes",draw:t=>{const{g:e,pose:a}=t,n=a.legs[o].foot,r=ut(t,n),i=n.x,s=n.y,l=a.sin*1.7,c=a.cos>.9;t.pal("main"),e.anchor(i,s);const f=s+(c?1.1:.4),h=i+l*.9,d=s-1.1+(c?.6:0),w=2.2+Math.abs(l)*.7,p=2;if(e.fill(h-w,d-p,h+w,f,(u,m)=>{const y=(u-h)/w,g=(m-d)/p,_=y*y+g*g;return _>1||m>f?-1:m>f-.6?0:e.t(y*z+g*mt+Math.sqrt(1-_)*Q,r)}),e.capsule(i,s-4.4,i,s-2,2.05,2.15,u=>e.t(u,r)),e.fill(i-2.7,s-5.9,i+2.7,s-4,(u,m)=>{const y=(u-i)/2.6;return Math.abs(y)>1||m<s-5.8||m>s-4.1?-1:e.t(y*z+Math.sqrt(1-y*y)*Q,r+(m>s-4.7?-.3:.3))}),e.clip=!0,e.line(i-2,s-3.8,i+2.2,s-3.8,V),r===0){if(e.dot(i-1.8,s-5.5,4),a.cos>.3){const u=i+a.sin*1.2;e.line(u-.8,s-2.6,u+.8,s-2.6,_t)}else a.cos<-.3?e.line(i,s-4,i,s-1.2,V):e.fold(i-1,s-3,i+1.6,s-2.3);e.dot(h-.8+l*.3,d-1,_t)}else e.line(i-2,s-3.3,i+2.2,s-3.3,1);e.clip=!1}}),Sa={id:"shoes_boots",name:"棕色短靴",slot:"shoes",palettes:{main:po},variants:[{id:"brown",name:"棕",palettes:{main:po}},{id:"black",name:"黑",palettes:{main:v("boots-black","#34343e")}}],parts:[mo(0),mo(1)]},Ia=Object.freeze(Object.defineProperty({__proto__:null,boots:Sa},Symbol.toStringTag,{value:"Module"})),rt=13.2;function ct(o,t,e=0){return o.g.t(t*1.35+e)}function ae(o){const t=e=>({layer:ue(e),draw:a=>{var f;const{g:n}=a,r=wt(a,e),i=ut(a,r.hand),s=(f=o.r)!=null?f:3,l=r.shoulder.x,c=r.shoulder.y+.6;if(a.pal(o.key),n.ellipse(l,c,s+.6,s*.85,(h,d,w)=>o.trimKey&&w>.45?(a.pal(o.trimKey),ct(a,h,i+.1)):(a.pal(o.key),ct(a,h,i))),o.spikes){a.pal(o.trimKey);const h=e==="R"?-1:1;for(const d of[-.5,.6]){const w=l+d*s*a.pose.cos*h;n.tri({x:w-1,y:c-s*.6},{x:w+1,y:c-s*.6},{x:w+.4*h*a.pose.cos,y:c-s-2.4},d<0?3:2)}}}});return o.only?[t(o.only)]:[t("L"),t("R")]}function uo(o,t,e,a,n){const{g:r}=o;if(o.pal(a),J(o,rt,{flare:2},(i,s,l)=>l<t||l>e?-1:l>e-.5?0:r.t(i,-.1)),n&&o.pose.cos>.3){const i=gt(o),s=o.pose.neckY;o.pal(n),r.rect(i-1.1,s+t,2.2,e-t,(l,c)=>l<i-.3||c<s+t+.5?4:1)}}const La=k("leather-armor","#140a06","#3c2412","#6a4224","#9a6a3a","#c8975c"),Ra=k("leather-strap","#0c0604","#24140a","#3e2614","#5e3c20","#80583a"),Ta=k("leather-brass","#2e1a06","#74501a","#b8862e","#e8c060","#fff0b0"),Ha=k("leather-linen","#3a3428","#7a7060","#b0a68e","#dcd2b8","#f6f0de"),Fa={id:"top_leather_armor",name:"皮甲",slot:"top",gameItem:"leatherArmor",palettes:{main:La,strap:Ra,metal:Ta,cloth:Ha},parts:[{layer:"top",draw:o=>{const{g:t,pose:e}=o,a=e.neckY,n=e.torsoHalf;o.pal("main"),J(o,rt,{flare:2.2},(r,i,s)=>s<2.4?0:s<3.4?1:t.t(r,s>6.6&&s<7.2?-.5:s>10.6?-.15:.05)),t.clip=!0;for(let r=e.torsoX(6)-n+1;r<e.torsoX(6)+n-.5;r+=1.6)t.dot(r,a+6.2,_t);if(e.cos>-.3){o.pal("strap");const r=e.cos;t.fill(e.torsoX(6)-n-1,a+2,e.torsoX(6)+n+1,a+12,(s,l)=>{const c=(l-a-2.5)/9,f=e.torsoX(6)+n*.9*r*(.8-1.7*c)+e.sin*n*.5;return Math.abs(s-f)<1.1?s<f-.3?3:2:-1}),o.pal("metal");const i=e.torsoX(6)+n*.9*r*(.8-1.7*.35)+e.sin*n*.5;t.dot(i,a+5.7,4)}t.clip=!1,uo(o,9.6,11.2,"strap","metal")}},...Mt({key:"cloth",length:.62,r:1.9}),...ae({key:"main",trimKey:"strap",r:2.8,only:"L"})]},Ea=k("rune-steel","#0a0e14","#222c3a","#3e4e62","#6a7e96","#a8bccc"),Na=k("rune-trim","#141820","#46505e","#7e8a98","#bcc6d0","#eef4fa"),$a=k("rune-glow","#06343a","#0e7a80","#28c6c0","#86f4e4","#e8fff8"),Oa=k("rune-cloth","#0a0a14","#1c1c34","#2e2e52","#46467a","#6a6aa4"),Ba={id:"top_rune_armor",name:"符文甲",slot:"top",gameItem:"runeArmor",palettes:{main:Ea,trim:Na,rune:$a,cloth:Oa},parts:[{layer:"top",draw:o=>{const{g:t,pose:e}=o,a=e.neckY;if(o.pal("main"),J(o,rt,{flare:2.4},(n,r,i)=>i<2.4?0:i>rt-2?(o.pal("trim"),ct(o,n,i>rt-.6?-.4:.1)):(o.pal("main"),ct(o,n,i>7.6&&i<8.3?-.8:i<3.4?-.5:0))),t.clip=!0,o.pal("rune"),e.cos>.3){const n=gt(o);t.line(n,a+3.6,n,a+7,3),t.dot(n,a+4.4,4),t.dot(n-2.6,a+5.4,2),t.dot(n+2.6,a+5.4,2),t.line(n-1.6,a+9.4,n+1.6,a+9.4,3)}else if(e.cos<-.3){const n=e.torsoX(5)-e.torsoHalf*.4*e.sin;t.line(n-2.4,a+5,n+2.4,a+5,3),t.dot(n,a+5,4)}else t.line(e.torsoX(5)+.6*e.sin,a+4,e.torsoX(5)+.6*e.sin,a+6.6,3);t.clip=!1}},...Mt({key:"cloth",cuffKey:"trim",r:2}),...ae({key:"main",trimKey:"trim",r:3.1}),oo,{layer:"arm_front",outline:!1,draw:o=>{const t=o.pose.armL.hand.front?o.pose.armL:o.pose.armR;o.pal("rune"),o.g.clip=!0,o.g.dot(t.shoulder.x,t.shoulder.y+.2,4),o.g.clip=!1},mask:"below"}]},va=k("star-armor","#1a1e2c","#5a6276","#9aa4b8","#d6dde8","#ffffff"),Ga=k("star-gold","#3a2206","#8a5a14","#d4a030","#f6d670","#fff8c8"),Ka=k("star-cloth","#08122e","#173064","#2a52a0","#4a7ed0","#86b4ee"),Pa=k("star-gem","#0e3a6a","#2a7ac0","#5cbcf0","#b0ecff","#ffffff"),Ua={id:"top_starlight_armor",name:"星辉甲",slot:"top",gameItem:"starlightArmor",palettes:{main:va,trim:Ga,cloth:Ka,gem:Pa},parts:[{layer:"top",draw:o=>{const{g:t,pose:e}=o,a=e.neckY;if(o.pal("cloth"),J(o,rt+.6,{flare:2.6},(n,r,i)=>i<9.5?-1:t.t(n,-.05)),o.pal("main"),J(o,10.2,{flare:.8},(n,r,i)=>i<2.4?0:i>9.3||Math.abs(Math.abs(r)-.97)<.03?(o.pal("trim"),ct(o,n,.15)):(o.pal("main"),ct(o,n,i<3.4?-.4:.1))),e.cos>.3){const n=gt(o),r=a+5.4;o.pal("gem"),t.clip=!0,t.fill(n-3.4,r-3.4,n+3.4,r+3.4,(i,s)=>{const l=Math.abs(i-n),c=Math.abs(s-r);return l+c>3.4||Math.min(l,c)>.6?-1:l+c<1?4:i<n||s<r?3:2}),t.clip=!1}else e.cos<-.3&&(o.pal("trim"),t.clip=!0,t.line(e.torsoX(5)-2,a+4.6,e.torsoX(5)+2,a+4.6,3),t.clip=!1)}},{layer:"top",draw:o=>uo(o,8.4,9.9,"trim","gem")},...Mt({key:"cloth",cuffKey:"main",r:2}),...ae({key:"main",trimKey:"trim",r:3.6}),ao]},Da=k("dragon-armor","#1e0408","#4e0c14","#8a1a20","#c43c30","#ee7a56"),Xa=k("dragon-gold","#341a04","#80500e","#c88e22","#f0c858","#fff2b8"),Ya=k("dragon-cloth","#08080a","#1a1a20","#2c2c34","#46464e","#6a6a72"),Ca={id:"top_dragon_armor",name:"龙纹甲",slot:"top",gameItem:"dragonArmor",palettes:{main:Da,trim:Xa,cloth:Ya,fx:k("dragon-flame","#7a1c0c","#d04a18","#f6902c","#ffd060","#fff6c8")},parts:[{layer:"top",draw:o=>{const{g:t,pose:e}=o,a=e.neckY;if(o.pal("main"),J(o,rt+.4,{flare:3},(n,r,i,s,l)=>{if(i<2.4)return 0;if(i>rt-1.8)return o.pal("trim"),ct(o,n,i>rt-.2?-.5:.1);o.pal("main");const c=Math.floor((l-a)/1.9),f=(s+c%2*1.3)/2.6,h=f-Math.floor(f)-.5,w=(l-a)/1.9-c>.72-h*h*1.2;return ct(o,n,(w?-.75:.05)+(i<3.4?-.4:0))}),e.cos>.3){const n=gt(o),r=a+4.2;o.pal("trim"),t.clip=!0,t.tri({x:n-2.2,y:r},{x:n+2.2,y:r},{x:n,y:r+3.4},3),t.dot(n,r+1,4),t.line(n-2.2,r,n-3.2,r-1.2,2),t.line(n+2.2,r,n+3.2,r-1.2,2),t.clip=!1}t.clip=!0,t.line(e.torsoX(3)-.4,a+3,e.torsoX(3)-.4,a+3,V),t.clip=!1}},...Mt({key:"cloth",cuffKey:"trim",r:2}),...ae({key:"main",trimKey:"trim",r:3.7,spikes:!0}),...no]},qa=Object.freeze(Object.defineProperty({__proto__:null,dragonArmor:Ca,leatherArmor:Fa,runeArmor:Ba,starlightArmor:Ua},Symbol.toStringTag,{value:"Module"})),wo=k("cloak-red","#2e0810","#701422","#b42a34","#e0584c","#fa9c84"),Wa=k("trim-gold","#3e2408","#8a5c16","#d8a430","#f6d86c","#fff6c0"),za=k("belt-leather","#140a06","#34200f","#583820","#80542e","#aa7a48"),Dt=12.8;function Ja(o){const{g:t,pose:e}=o,{sin:a,cos:n}=e,r=n<.3,i=e.anim==="walk",s=i?Math.sin(e.phase+1):0,l=6.6*Math.abs(n)+3*Math.abs(a)+1.2,c=l+3.8,f=e.torsoX(3)-a*3.8,h=e.neckY-.5,d=Et-6,w=2.2+Math.abs(n)*1.4;t.grit=.24,t.fill(f-c-6,h,f+c+6,d+2,(p,u)=>{const m=Math.min(1,(u-h)/(d-h));if(m<0)return-1;const y=f+s*m*1.6-a*m*2.4,g=l+(c-l)*m,_=(p-y)/g;if(Math.abs(_)>1)return-1;const x=_*w*Math.PI+m*s*.8,b=d+.9*Math.sin(x+.6)+.5*Math.sin(x*2.7+1)+(i?.5*Math.sin(e.phase*2+_*2):0);if(u>b)return-1;const A=Math.min(1,m*1.7),j=Math.sin(x+.9)*A;if(!r)return o.pal("main"),j>.3?1:0;let I=.18+_*z*.9+j*.75;m<.12&&(I-=.6);const T=b-u;return T>1.4&&T<3.2?(o.pal("trim"),t.t(I,.25)):(o.pal("main"),t.t(I))})}function Qa(o){const{g:t,pose:e}=o,a=e.neckY,n=e.torsoHalf+2.9,r=a-2,i=a+4.6,s=e.torsoX(1);if(t.fill(s-n,r,s+n,i+1.4,(l,c)=>{const f=(l-s)/n;if(Math.abs(f)>1)return-1;const h=r+2.9*(1-Math.sqrt(1-f*f)),d=i+.7*Math.cos(f*n*.9);if(c<h||c>d)return-1;const w=(c-r)/(i-r),p=f*z+(w*1.5-.75)*mt+Math.sqrt(1-f*f)*Q*.85,u=d-c;return u>.6&&u<2?(o.pal("trim"),t.t(p,.2)):(o.pal("main"),t.t(p))}),e.cos>.3){const l=gt(o);o.pal("trim"),t.ellipse(l,a+1.4,1.3,1.3,c=>c>.5?4:c>-.1?3:1)}}const Va={id:"top_red_cloak",name:"红色斗篷装",slot:"top",palettes:{main:wo,trim:Wa,belt:za},variants:[{id:"red",name:"红",palettes:{main:wo}},{id:"forest",name:"墨绿",palettes:{main:v("cloak-forest","#2c6e48")}},{id:"night",name:"夜蓝",palettes:{main:v("cloak-night","#34428c")}}],layerOverride:o=>o==="N"||o==="NE"?{cape:Le.mantle-1}:{},parts:[{layer:"cape",draw:Ja},{layer:"top",draw:o=>{const{g:t,pose:e}=o,a=e.torsoHalf,n=e.neckY;if(o.pal("main"),J(o,Dt,{flare:1.6},(r,i,s)=>s>Dt-1.6?-1:t.t(r,s>9.8?-.1:0)),o.pal("trim"),J(o,Dt,{flare:1.6},(r,i,s)=>s<=Dt-1.6?-1:t.t(r,.2)),o.pal("belt"),J(o,Dt,{flare:1.6},(r,i,s)=>s<8||s>9.8?-1:s<8.6?3:s>9.3?0:t.t(r,-.25)),t.clip=!0,o.pal("main"),t.fold(e.torsoX(5)-a+1,n+4.6,e.torsoX(5)-a+3.6,n+7.2),t.fold(e.torsoX(5)+a-1,n+4.2,e.torsoX(5)+a-3.2,n+6.8),e.cos>.3){const r=gt(o);o.pal("trim"),t.S>=.8&&t.line(r,n+4.6,r,n+7.6,2),t.rect(r-1.2,n+7.8,2.4,2.4,(i,s)=>i<r-.4||s<n+8.5?4:1)}else t.line(e.torsoX(5),n+4,e.torsoX(5),n+7.6,V);t.clip=!1}},...Mt({key:"main",cuffKey:"trim"}),{layer:"mantle",draw:Qa}]},Za=Object.freeze(Object.defineProperty({__proto__:null,redCloak:Va},Symbol.toStringTag,{value:"Module"})),go=k("jacket-blue","#0c1430","#1c3464","#2f589e","#5288cc","#a0c8f0"),tn=k("trim-white","#3c4258","#8088a0","#c2c4c8","#ece8dc","#fffcf2"),en=k("button-gold","#3e2408","#8a5c16","#d8a430","#f6d86c","#fff6c0"),ne=13.2,on=3,an={id:"top_traveler",name:"蓝色旅人装",slot:"top",palettes:{main:go,trim:tn,metal:en},variants:[{id:"blue",name:"蓝",palettes:{main:go}},{id:"green",name:"绿",palettes:{main:v("jacket-green","#3a8a54")}},{id:"purple",name:"紫",palettes:{main:v("jacket-purple","#6e4eb0")}}],parts:[{layer:"top",draw:o=>{const{g:t,pose:e}=o,a=e.torsoHalf,n=e.neckY,r=ne-on;if(o.pal("main"),J(o,ne,{flare:2},(i,s,l)=>l>r?-1:l<2.6?0:l<3.6||l>r-.6?1:t.t(i,l>7&&l<10?-.12:.05)),o.pal("trim"),J(o,ne,{flare:2},(i,s,l)=>l<=r?-1:t.t(i,l>ne-.7?-.35:.3)),o.pal("main"),t.clip=!0,t.fold(e.torsoX(6)-a+1,n+4.8,e.torsoX(6)-a+3.8,n+7.4),t.fold(e.torsoX(6)+a-1,n+4.4,e.torsoX(6)+a-3.4,n+7),e.cos>.3){const i=gt(o);t.line(i,n+3,i,n+r-.6,V),o.pal("trim"),t.tri({x:i,y:n+2.2},{x:i-3.8,y:n+2.8},{x:i-.4,y:n+7},3),t.tri({x:i,y:n+2.2},{x:i+3.8,y:n+2.8},{x:i+.4,y:n+7},2),o.pal("metal");for(const s of[7,9])t.dot(i+1.2,n+s,4),t.dot(i+1.2,n+s+1,1)}else if(e.cos<-.3){const i=e.torsoX(5)-a*.4*e.sin;t.line(i,n+3.5,i,n+7,V),t.rect(i-3.4,n+7.4,6.8,1.6,(s,l)=>l<n+8.1?3:1),o.pal("metal"),t.dot(i-3,n+7.8,4),t.dot(i+3,n+7.8,3)}else t.line(e.torsoX(7)-.6,n+5,e.torsoX(7)-.6,n+r-1,V),t.line(e.torsoX(8)+.6,n+8.6,e.torsoX(8)+3,n+8.6,_t);t.clip=!1}},...Mt({key:"main",cuffKey:"trim"})]},nn=Object.freeze(Object.defineProperty({__proto__:null,travelerJacket:an},Symbol.toStringTag,{value:"Module"})),rn=k("greatsword-steel","#10141e","#4a5468","#8c9aae","#cad6e4","#f6faff"),sn=k("greatsword-hilt","#121216","#3c3c46","#6c6c78","#a2a2ac","#d8d8e0"),ln=k("greatsword-grip","#120806","#2e1a0e","#523420","#7a5232","#a07648"),cn=k("fx-heavy","#5c6a80","#a0b0c4","#d6e0ec","#f2f6fc","#ffffff"),hn=k("greatsword-ruby","#2a0408","#6a0c16","#c0202c","#f05a5a","#ffd0c8"),fn={from:4.2,to:31,half:2,tip:4,core:"fuller",grip:5,guard:[4.6,1.6,.8],pommel:1.5},dn={id:"weapon_great_sword",name:"重剑",slot:"weapon_main",hold:"shoulder",gameItem:"greatSword",palettes:{blade:rn,hilt:sn,grip:ln,gem:hn,fx:cn},parts:[{layer:"weapon",draw:o=>St(o,fn,!0)},eo,jt(9,34),At(o=>O(o,28),"fx",.9)]},pn=k("fang-blade","#3a0a04","#a02a0c","#e8601c","#ffa83a","#fff0b0"),mn=k("fang-hilt","#120a10","#2e1e2a","#54404c","#8a6a70","#c0a0a0"),un=k("fang-grip","#0e0606","#2a1012","#4a1e1e","#6e3028","#94503c"),yo=k("fx-ember","#7a1c0c","#d04a18","#f6902c","#ffd060","#fff6c8"),wn={from:4,to:29,half:2.3,tip:11,curve:-1.8,core:"glow",grip:4.6,guard:[5.4,1.8,2.6],pommel:1.4},gn={id:"weapon_dragon_fang",name:"龙牙剑",slot:"weapon_main",hold:"shoulder",gameItem:"dragonFangSword",palettes:{blade:pn,hilt:mn,grip:un,gem:yo,fx:yo},parts:[{layer:"weapon",draw:o=>St(o,wn,!0)},Ze,jt(9,32),At(o=>O(o,26),"fx",1)]},yn=Object.freeze(Object.defineProperty({__proto__:null,dragonFangSword:gn,greatSword:dn},Symbol.toStringTag,{value:"Module"})),bn=k("bow-wood","#1a0e06","#4e2e14","#86562a","#bc8644","#e8b874"),xn=k("bow-wrap","#0e1408","#24341a","#3e5a2a","#62843e","#90b062"),kn=k("bow-string","#3a3628","#8a826a","#c8c0a4","#ece6d0","#ffffff"),_n=k("bow-arrow","#1a1410","#5a4a38","#9a8466","#d2c0a0","#fff4dc"),Mn=k("bow-fletch","#3a0c0c","#8a2420","#c84a3a","#ec8a6a","#ffd0b8"),Xt=13,jn={id:"weapon_hunting_bow",name:"猎弓",slot:"weapon_main",hold:"bow",gameItem:"huntingBow",palettes:{wood:bn,wrap:xn,string:kn,arrow:_n,fletch:Mn},parts:[{layer:"weapon",draw:o=>bo(o,!0)},{layer:"weapon",outline:!1,draw:o=>bo(o,!1)}]};function bo(o,t){{const e=lt(o);if(!e)return;const{g:a,pose:n}=o,r=n.sin,i=n.cos*.35,s=-e.dy,l=e.dx,c=s*r+l*i,f=c>=0?1:-1,h=2.4*Math.max(.35,Math.min(1,Math.abs(c)*1.4)),d=g=>{const _=-f*h*(g/Xt)**2;return{x:e.x+e.dx*g*e.k+s*_,y:e.y+e.dy*g*e.k+l*_}},w=Array.from({length:13},(g,_)=>d(-Xt+_*2*Xt/12));if(t){o.pal("wood"),a.ribbon(w,g=>.95-.45*Math.abs(g-.5)*2,(g,_)=>_<-.3?3:_>.4?1:a.t(g)>3?4:2),o.pal("wrap"),a.ribbon([d(-1.8),d(0),d(1.8)],()=>1.05,(g,_)=>_<0?3:1);return}const p=d(Xt),u=d(-Xt),m=n.fx==="arrow",y=n.handR;if(o.pal("string"),m&&n.anim==="shoot"){a.line(p.x,p.y,y.x,y.y+.4,3),a.line(u.x,u.y,y.x,y.y+.4,2);const g=n.sin,_=n.cos*.35+.02,x=Math.hypot(g,_)||1,b=g/x,A=_/x,j=15*(.4+.6*Math.min(1,x)),I=y.x+b*j,T=y.y+.4+A*j;o.pal("arrow"),a.line(y.x,y.y+.4,I,T,3),a.dot(I,T,4),o.pal("fletch"),a.dot(y.x+b*1.2,y.y+.4+A*1.2-.6,3),a.dot(y.x+b*1.2,y.y+.4+A*1.2+.6,2)}else a.line(p.x,p.y,u.x,u.y,2);if(n.fx==="loose"){const g=n.sin,_=n.cos*.35+.02,x=Math.hypot(g,_)||1,b=g/x,A=_/x,j=e.x+b*8,I=e.y+A*8;o.pal("arrow"),a.line(j,I,j+b*12,I+A*12,4),o.pal("string"),a.line(j-b*3,I-A*3+1,j+b*4,I+A*4+1,3)}}}const An=Object.freeze(Object.defineProperty({__proto__:null,huntingBow:jn},Symbol.toStringTag,{value:"Module"})),Sn=k("steel","#141a28","#56647e","#a0b0c6","#dce8f2","#ffffff"),In=k("hilt-gold","#3e2408","#8a5c16","#d8a430","#f6d86c","#fff6c0"),Ln=k("grip-leather","#140a06","#34200f","#583820","#80542e","#aa7a48"),xo=k("fx-swish","#5a6c88","#9eb2cc","#d4e2f0","#f2f8ff","#ffffff"),Rn={from:3.8,to:19.5,half:1.15,tip:4,grip:2.4,guard:[3.3,1.2,.6],pommel:1.2},Tn={id:"weapon_short_sword",name:"短剑",slot:"weapon_main",hold:"down",palettes:{blade:Sn,hilt:In,grip:Ln,fx:xo},parts:[{layer:"weapon",draw:o=>St(o,Rn)},jt(6,22)]},Hn=k("iron-dull","#16161a","#4a4a52","#7a7a80","#a8a6a0","#d0ccc0"),Fn=k("grip-wood","#180e08","#4a2e18","#7c522a","#aa7a40","#d4a460"),En={from:3.2,to:17,half:1.1,tip:2.2,core:"fuller",grip:2.6,guard:[2.8,1.2,0],pommel:1},Nn={id:"weapon_training_sword",name:"训练短剑",slot:"weapon_main",hold:"down",gameItem:"trainingSword",palettes:{blade:Hn,hilt:v("hilt-iron","#6a6a70"),grip:Fn,fx:xo},parts:[{layer:"weapon",draw:o=>St(o,En)},jt(5,20)]},$n=Object.freeze(Object.defineProperty({__proto__:null,shortSword:Tn,trainingSword:Nn},Symbol.toStringTag,{value:"Module"})),On=k("staff-wood","#180e08","#4a2e18","#7c522a","#aa7a40","#d4a460"),Bn=k("staff-gold","#3e2408","#8a5c16","#d8a430","#f6d86c","#fff6c0"),re=k("staff-gem","#082a44","#147aa0","#30c2dc","#90f0f4","#f0ffff");function ko(o,t,e,a){o.g.ellipse(t,e,a,a,n=>n>.8?4:n>.4?3:n>-.15?2:1),o.g.dot(t-a*.4,e-a*.4,4)}function vn(o){const t=lt(o);if(!t)return;const{g:e}=o;o.pal("wood"),Z(o,t,-11,34.5,.75,(s,l)=>{if(s>-2&&s<2.8)return l>.2?1:Math.floor(s*1.2+10)%2?2:3;const c=Math.abs((s+40)%7-3.5)<.5;return l<0?c?2:3:1}),o.pal("gold"),Z(o,t,33.6,35.6,1.2,(s,l)=>l<-.4?4:l>.5?1:3),Z(o,t,-12.4,-11,1.05,(s,l)=>l<0?3:1);const{x:a,y:n}=O(t,40),{dx:r,dy:i}=t;e.fill(a-6,n-6,a+6,n+6,(s,l)=>{const c=s-a,f=l-n,h=Math.hypot(c,f),d=(c*r+f*i)/(h||1),w=.8*Math.max(0,1-Math.max(0,d+.2)*1.1);if(Math.abs(h-4.2)>w||d>.62)return-1;const p=-(c*.56+f*.62)/h;return p>.55?4:p>0?3:p>-.6?2:1}),o.pal("gem"),ko(o,a,n,2.7),e.dot(a+r*4.5-i*2.4,n+i*4.5+r*2.4,4),e.dot(a-i*5+r,n+r*5+i,3)}const Gn={id:"weapon_staff",name:"法杖",slot:"weapon_main",palettes:{wood:On,gold:Bn,gem:re,fx:re},variants:[{id:"aqua",name:"水蓝宝珠",palettes:{gem:re,fx:re}},{id:"ember",name:"炽红宝珠",palettes:{gem:v("staff-gem-ember","#e8552c"),fx:v("staff-gem-ember","#e8552c")}},{id:"violet",name:"紫晶宝珠",palettes:{gem:v("staff-gem-violet","#9a5ce0"),fx:v("staff-gem-violet","#9a5ce0")}}],parts:[{layer:"weapon",draw:vn},At(o=>O(o,40),"fx",1)]},Kn=k("scepter-gold","#3a1c04","#8a5410","#d89a26","#f8d468","#fffbd0"),_o=k("scepter-gem","#2a0420","#7a1050","#c42a80","#f070b4","#ffd8f0"),Pn=k("scepter-shaft","#0c0a18","#24203c","#3e3864","#625a94","#9088c4");function Un(o){const t=lt(o);if(!t)return;const{g:e}=o,{dx:a,dy:n}=t;o.pal("shaft"),Z(o,t,-9,31,.8,(l,c)=>c<-.1?3:c>.4?1:2),o.pal("gold"),e.clip=!0,Z(o,t,-9,31,.8,(l,c)=>Math.abs((l*.55+c*.9+20)%2-1)<.32?c<0?4:3:-1),e.clip=!1,Z(o,t,-10.6,-9,1.2,(l,c)=>c<0?3:1),Z(o,t,30,32.4,1.5,(l,c)=>c<-.4?4:c>.6?1:3);const{x:r,y:i}=O(t,37.5);for(const l of[-1,1])e.fill(r-8,i-8,r+8,i+8,(c,f)=>{const h=c-r,d=f-i,w=-(h*a+d*n),p=(h*-n+d*a)*l;if(w<-4.5||w>4.5)return-1;const u=3.2+2.6*Math.cos((w+.5)/5*1.4)-Math.max(0,-w-2)*.9;if(p<2.2||p>u)return-1;const m=Math.abs((p+w*.6+20)%1.6-.8)<.22,y=l<0?.4:-.2;return m?1:y-w*.08>.2?4:y>0?3:2});o.pal("gem"),ko(o,r,i,3.1),o.pal("gold");const s=O(t,43.2);e.fill(s.x-4,s.y-3,s.x+4,s.y+3,(l,c)=>{const f=(l-s.x)/3.4,h=(c-s.y)/1.3,d=Math.hypot(f,h);return Math.abs(d-1)<.28?h<0?4:3:-1})}const Dn={id:"weapon_legendary_staff",name:"传奇权杖",slot:"weapon_main",gameItem:"legendaryStaff",palettes:{shaft:Pn,gold:Kn,gem:_o,fx:_o},parts:[{layer:"weapon",draw:Un},Ve,At(o=>O(o,37.5),"fx",1.2)]},Xn=Object.freeze(Object.defineProperty({__proto__:null,legendaryStaff:Dn,staff:Gn},Symbol.toStringTag,{value:"Module"})),Yn=k("starlight-crystal","#0e2448","#2a64a8","#5aa6e0","#a8e0fa","#f4ffff"),Cn=k("starlight-silver","#1c2232","#5a6478","#a4aec0","#dce4ee","#ffffff"),qn=k("starlight-grip","#0a0c1c","#1c2450","#2e3c80","#4a5eb0","#7a8ed8"),Mo=k("fx-star","#2a5a9a","#5aa0e0","#9ad8f8","#d8f4ff","#ffffff"),Wn={from:3.6,to:21.5,half:1.6,tip:5,core:"glow",grip:2.6,guard:[3.6,1.2,1.2],pommel:1.2},zn={id:"weapon_starlight_blade",name:"星辉刃",slot:"weapon_main",hold:"down",gameItem:"starlightBlade",palettes:{blade:Yn,hilt:Cn,grip:qn,gem:Mo,fx:Mo},parts:[{layer:"weapon",draw:o=>St(o,Wn,!0)},to,jt(6,23),At(o=>O(o,19),"fx",.9)]},Jn=Object.freeze(Object.defineProperty({__proto__:null,starlightBlade:zn},Symbol.toStringTag,{value:"Module"})),Qn={id:"hair_bun",name:"盘发",palette:["#100a0c","#2a1a1c","#4a2e2e","#7a4a44","#b07a6a"],style:{clump:.7,global:.75,ring:!0,streaks:!0,grit:.04,dither:!1,closeHoles:!0,seamFloor:1.5,floor:1,innerLine:1.25},hairline:[[0,46],[60,50],[100,94],[100,112],[180,118]],locks:[{phi:-40,a1:66,twist:26,flick:1.14,width:3.2,tip:.65},{phi:-12,a1:62,twist:30,flick:1.14,width:3.4,tip:.65},{phi:16,a1:58,twist:30,flick:1.16,width:3,tip:.65},{phi:-96,a1:100,twist:6,flick:1.12,width:3.2,tip:.8,taper:.7,drop:5,spread:.4},{phi:96,a1:100,twist:-6,flick:1.12,width:3.2,tip:.8,taper:.7,drop:5,spread:.4},{phi:56,a1:70,twist:60,flick:1.06,width:3.4,tip:.65},{phi:-70,a1:74,twist:-50,flick:1.06,width:3.4,tip:.65},{phi:130,a1:112,twist:30,flick:1.04,width:4.2,tip:.65},{phi:-130,a1:112,twist:-30,flick:1.04,width:4.2,tip:.65},{phi:160,a1:108,twist:14,flick:1.04,width:4.4,tip:.65},{phi:-160,a1:108,twist:-14,flick:1.04,width:4.4,tip:.65},{phi:150,a0:30,a1:52,flick:.92,lift:.62,width:3.3,tier:1,tip:1.8,taper:.45,twist:0},{phi:180,a0:28,a1:54,flick:.92,lift:.62,width:3.3,tier:1,tip:1.8,taper:.45,twist:0},{phi:-150,a0:30,a1:52,flick:.92,lift:.62,width:3.3,tier:1,tip:1.8,taper:.45,twist:0},{phi:165,a0:24,a1:44,flick:.92,lift:.62,width:3.3,tier:1,tip:1.8,taper:.45,twist:0},{phi:-165,a0:24,a1:44,flick:.92,lift:.62,width:3.3,tier:1,tip:1.8,taper:.45,twist:0},{phi:180,a0:40,a1:60,flick:.92,lift:.62,width:3.3,tier:1,tip:1.8,taper:.45,twist:0}]},Vn={id:"hair_long",name:"披肩发",palette:["#100a0c","#2e1c1a","#553228","#8a5a40","#c8946a"],style:{clump:.7,global:.75,ring:!0,streaks:!0,grit:.04,dither:!1,closeHoles:!0,seamFloor:1.5,floor:1,innerLine:1.25},hairline:[[0,50],[70,50],[96,96],[96,118],[180,128]],locks:[{phi:-50,a1:62,twist:-10,flick:1.12,width:3.2,tip:.65},{phi:-24,a1:66,twist:-8,flick:1.12,width:3.4,tip:.65},{phi:0,a1:68,twist:-6,flick:1.12,width:3.4,tip:.65},{phi:24,a1:64,twist:-4,flick:1.12,width:3.4,tip:.65},{phi:50,a1:60,twist:4,flick:1.12,width:3.2,tip:.65},{phi:-86,a1:100,twist:4,flick:1.04,width:2.8,tip:.9,taper:.8,drop:8,spread:-.6},{phi:86,a1:100,twist:-4,flick:1.04,width:2.8,tip:.9,taper:.8,drop:8,spread:-.6},{phi:-112,a1:108,twist:0,flick:1.04,width:3,tip:.9,taper:.8,drop:12,spread:-.3},{phi:112,a1:108,twist:0,flick:1.04,width:3,tip:.9,taper:.8,drop:12,spread:-.3},{phi:140,a1:114,twist:0,flick:1.04,width:3.2,tip:.9,taper:.8,drop:14,spread:-.3},{phi:-140,a1:114,twist:0,flick:1.04,width:3.2,tip:.9,taper:.8,drop:14,spread:-.3},{phi:164,a1:118,twist:0,flick:1.04,width:3.2,tip:.9,taper:.8,drop:14,spread:-.3},{phi:-164,a1:118,twist:0,flick:1.04,width:3.2,tip:.9,taper:.8,drop:14,spread:-.3},{phi:-150,a0:2,a1:36,twist:18,flick:1.3,lift:.04,width:2.8,tier:1,tip:.6},{phi:-40,a0:2,a1:34,twist:24,flick:1.3,lift:.04,width:2.6,tier:1,tip:.6},{phi:60,a0:2,a1:34,twist:-20,flick:1.3,lift:.04,width:2.6,tier:1,tip:.6},{phi:150,a0:2,a1:36,twist:-18,flick:1.3,lift:.04,width:2.8,tier:1,tip:.6}]},Zn={id:"hair_messy",name:"蓬松短发",palette:["#1c100c","#4a2a1a","#7c4a2a","#b47c42","#ecc27a"],variants:[{id:"brown",name:"棕色",palette:["#1c100c","#4a2a1a","#7c4a2a","#b47c42","#ecc27a"]},{id:"black",name:"墨黑",palette:["#08080e","#1a1a26","#30323e","#52566a","#9098b0"]},{id:"blonde",name:"金色",palette:["#4a2c10","#96641e","#d4a036","#f2cc5e","#fff2ac"]},{id:"red",name:"赤红",base:"#b03a26"},{id:"silver",name:"银白",palette:["#2e3246","#6a7088","#a8b0c2","#d8dee8","#ffffff"]},{id:"teal",name:"青绿",base:"#2a8e84"}],hairline:[[0,50],[70,50],[100,95],[100,118.02],[180,129]],locks:[{phi:-47.26,a1:63.06,twist:16,width:3.3},{phi:-16.02,a1:72.16,twist:16,width:3.3},{phi:13.55,a1:66.35,twist:16,width:3.3},{phi:41.44,a1:61.39,twist:16,width:3.3},{phi:100,a1:96,flick:1.08,width:3.4},{phi:-100,a1:96,flick:1.08,width:3.4},{phi:125.28,a1:127.97,twist:4.28,width:3.8},{phi:158.46,a1:126.81,twist:6.9,width:3.8},{phi:-167.29,a1:126.08,twist:1.91,width:3.8},{phi:-138.69,a1:123.94,twist:-7.48,width:3.8},{phi:-150,a0:3,a1:40,twist:18,flick:1.18,lift:.04,width:2.6,tier:1},{phi:-40,a0:3,a1:40,twist:18,flick:1.18,lift:.04,width:2.6,tier:1},{phi:75,a0:3,a1:40,twist:18,flick:1.18,lift:.04,width:2.6,tier:1},{phi:30,a0:0,a1:34,twist:40,flick:1.6,lift:.04,width:.9,tier:2}]},t0={id:"hair_neat",name:"利落短发",palette:["#08080e","#1a1a26","#30323e","#52566a","#9098b0"],variants:[{id:"black",name:"墨黑",palette:["#08080e","#1a1a26","#30323e","#52566a","#9098b0"]},{id:"brown",name:"棕色",palette:["#1c100c","#4a2a1a","#7c4a2a","#b47c42","#ecc27a"]},{id:"ash",name:"灰褐",base:"#7a6a5a"}],hairline:[[0,48],[70,48],[100,86],[100,106],[180,116]],locks:[{phi:-52,a1:62,twist:30,width:3.4},{phi:-20,a1:68,twist:30,width:3.4},{phi:12,a1:63,twist:30,width:3.4},{phi:42,a1:57,twist:30,width:3.2},{phi:98,a1:88,flick:1.04,width:3.2},{phi:-98,a1:88,flick:1.04,width:3.2},{phi:132,a1:114,flick:1.05,width:3.8},{phi:168,a1:116,flick:1.05,width:3.8},{phi:-150,a1:114,flick:1.05,width:3.8},{phi:-120,a0:3,a1:38,twist:24,flick:1.16,lift:.04,width:2.4,tier:1},{phi:60,a0:3,a1:36,twist:24,flick:1.16,lift:.04,width:2.4,tier:1}]},e0={id:"hair_ponytail",name:"高马尾",palette:["#1e0c0a","#4e2410","#8a4a1e","#c88a3a","#f2c878"],style:{clump:.7,global:.75,ring:!0,streaks:!0,grit:.04,dither:!1,closeHoles:!0,seamFloor:1.5,floor:1,innerLine:1.25},hairline:[[0,46],[60,50],[100,94],[100,112],[180,118]],locks:[{phi:-40,a1:66,twist:26,flick:1.14,width:3.2,tip:.65},{phi:-12,a1:62,twist:30,flick:1.14,width:3.4,tip:.65},{phi:16,a1:58,twist:30,flick:1.16,width:3,tip:.65},{phi:-96,a1:100,twist:6,flick:1.12,width:3.2,tip:.8,taper:.7,drop:5,spread:.4},{phi:96,a1:100,twist:-6,flick:1.12,width:3.2,tip:.8,taper:.7,drop:5,spread:.4},{phi:56,a1:70,twist:60,flick:1.06,width:3.4,tip:.65},{phi:-70,a1:74,twist:-50,flick:1.06,width:3.4,tip:.65},{phi:130,a1:112,twist:30,flick:1.04,width:4.2,tip:.65},{phi:-130,a1:112,twist:-30,flick:1.04,width:4.2,tip:.65},{phi:160,a1:108,twist:14,flick:1.04,width:4.4,tip:.65},{phi:-160,a1:108,twist:-14,flick:1.04,width:4.4,tip:.65},{phi:180,a0:60,a1:76,flick:1.26,lift:.1,width:3,taper:.82,tip:1,drop:24,spread:0,twist:0}]},o0={id:"hair_side_tail",name:"侧马尾",palette:["#1e0c0a","#4e2410","#8a4a1e","#c88a3a","#f2c878"],style:{clump:.7,global:.75,ring:!0,streaks:!0,grit:.04,dither:!1,closeHoles:!0,seamFloor:1.5,floor:1,innerLine:1.25},hairline:[[0,46],[60,50],[100,94],[100,112],[180,118]],locks:[{phi:-40,a1:66,twist:26,flick:1.14,width:3.2,tip:.65},{phi:-12,a1:62,twist:30,flick:1.14,width:3.4,tip:.65},{phi:16,a1:58,twist:30,flick:1.16,width:3,tip:.65},{phi:-96,a1:100,twist:6,flick:1.12,width:3.2,tip:.8,taper:.7,drop:5,spread:.4},{phi:96,a1:100,twist:-6,flick:1.12,width:3.2,tip:.8,taper:.7,drop:5,spread:.4},{phi:56,a1:70,twist:60,flick:1.06,width:3.4,tip:.65},{phi:-70,a1:74,twist:-50,flick:1.06,width:3.4,tip:.65},{phi:130,a1:112,twist:30,flick:1.04,width:4.2,tip:.65},{phi:-130,a1:112,twist:-30,flick:1.04,width:4.2,tip:.65},{phi:160,a1:108,twist:14,flick:1.04,width:4.4,tip:.65},{phi:-160,a1:108,twist:-14,flick:1.04,width:4.4,tip:.65},{phi:-128,a0:62,a1:86,flick:1.2,lift:.1,width:2.9,taper:.82,tip:1,drop:18,spread:.8,twist:0}]},a0={id:"hair_swept",name:"侧分碎发",palette:["#1e0c0a","#4e1e16","#86362a","#c0603e","#f0a070"],style:{clump:.7,global:.75,ring:!1,streaks:!0,grit:.04,dither:!1,closeHoles:!0,seamFloor:1.5,floor:1,innerLine:1.25},hairline:[[0,48],[70,48],[100,92],[100,116],[180,126]],locks:[{phi:-62,a1:70,twist:30,flick:1.1600000000000001,width:3.2,tip:.65},{phi:-36,a1:80,twist:32,flick:1.1400000000000001,width:3.6,tip:.65},{phi:-8,a1:74,twist:34,flick:1.1400000000000001,width:3.4,tip:.65},{phi:20,a1:66,twist:34,flick:1.1800000000000002,width:3.2,tip:.65},{phi:48,a1:62,twist:30,flick:1.22,width:3,tip:.65},{phi:96,a1:104,twist:-6,flick:1.14,width:3.2,tip:.65},{phi:-96,a1:98,twist:6,flick:1.14,width:3.2,tip:.65},{phi:132,a1:122,twist:10,flick:1.16,width:3.6,tip:.65},{phi:162,a1:128,twist:-8,flick:1.12,width:3.8,tip:.65},{phi:-166,a1:124,twist:10,flick:1.14,width:3.8,tip:.65},{phi:-134,a1:120,twist:-10,flick:1.16,width:3.6,tip:.65},{phi:-170,a0:2,a1:40,twist:20,flick:1.55,lift:.05,width:2.8,tier:1,tip:.5},{phi:-120,a0:2,a1:38,twist:26,flick:1.6,lift:.05,width:2.8,tier:1,tip:.5},{phi:-60,a0:2,a1:36,twist:30,flick:1.6,lift:.05,width:2.6,tier:1,tip:.5},{phi:-10,a0:2,a1:34,twist:34,flick:1.55,lift:.05,width:2.6,tier:1,tip:.5},{phi:50,a0:2,a1:38,twist:28,flick:1.6,lift:.05,width:2.6,tier:1,tip:.5},{phi:110,a0:2,a1:40,twist:24,flick:1.55,lift:.05,width:2.8,tier:1,tip:.5}]},n0={id:"hair_tied",name:"小束",palette:["#140c0a","#2e1c16","#4e3226","#7a523a","#a87c58"],style:{clump:.7,global:.75,ring:!1,streaks:!0,grit:.04,dither:!1,closeHoles:!0,seamFloor:1.5,floor:1,innerLine:1.25},hairline:[[0,48],[70,48],[100,92],[100,116],[180,126]],locks:[{phi:-62,a1:70,twist:30,flick:1.1600000000000001,width:3.2,tip:.65},{phi:-36,a1:80,twist:32,flick:1.1400000000000001,width:3.6,tip:.65},{phi:-8,a1:74,twist:34,flick:1.1400000000000001,width:3.4,tip:.65},{phi:20,a1:66,twist:34,flick:1.1800000000000002,width:3.2,tip:.65},{phi:48,a1:62,twist:30,flick:1.22,width:3,tip:.65},{phi:96,a1:104,twist:-6,flick:1.14,width:3.2,tip:.65},{phi:-96,a1:98,twist:6,flick:1.14,width:3.2,tip:.65},{phi:132,a1:122,twist:10,flick:1.16,width:3.6,tip:.65},{phi:162,a1:128,twist:-8,flick:1.12,width:3.8,tip:.65},{phi:-166,a1:124,twist:10,flick:1.14,width:3.8,tip:.65},{phi:-134,a1:120,twist:-10,flick:1.16,width:3.6,tip:.65},{phi:-60,a0:2,a1:36,twist:30,flick:1.6,lift:.05,width:2.6,tier:1,tip:.5},{phi:50,a0:2,a1:38,twist:28,flick:1.6,lift:.05,width:2.6,tier:1,tip:.5},{phi:180,a0:58,a1:72,flick:1.42,lift:.14,width:2.7,taper:.6,tip:.9,drop:11,spread:0,twist:0}]},r0={colors:[{id:"brown",name:"棕色",palette:["#1c100c","#4a2a1a","#7c4a2a","#b47c42","#ecc27a"]},{id:"chestnut",name:"栗红",palette:["#1e0c0a","#4e1e16","#86362a","#c0603e","#f0a070"]},{id:"black",name:"墨黑",palette:["#08080e","#1a1a26","#30323e","#52566a","#9098b0"]},{id:"blonde",name:"金色",palette:["#4a2c10","#96641e","#d4a036","#f2cc5e","#fff2ac"]},{id:"silver",name:"银白",palette:["#2e3246","#6a7088","#a8b0c2","#d8dee8","#ffffff"]},{id:"red",name:"赤红",base:"#b03a26"},{id:"teal",name:"青绿",base:"#2a8e84"},{id:"navy",name:"深蓝",base:"#2c3e7a"},{id:"pink",name:"樱粉",base:"#d77a98"},{id:"violet",name:"紫",base:"#6a4aa8"}]},i0={id:"face_round",name:"圆眼",palettes:{eye:["#17101e","#1e3a5c","#3e9aa8","#8ad8d8","#ffffff"],blush:["#a85048","#cc7466","#e08a78","#f0a894","#fcd0c8"]},variants:[{id:"teal",name:"青瞳",palettes:{eye:["#17101e","#1e3a5c","#3e9aa8","#8ad8d8","#ffffff"]}},{id:"amber",name:"琥珀瞳",palettes:{eye:["#1e120a","#5a3410","#c07a20","#f0c060","#ffffff"]}},{id:"violet",name:"紫瞳",palettes:{eye:["#160e22","#3a2266","#7a52c0","#c0a0f0","#ffffff"]}},{id:"blue",name:"蓝瞳",palettes:{eye:["#14101e","#1c2e6a","#3a64c4","#86b4f4","#ffffff"]}},{id:"green",name:"绿瞳",palettes:{eye:["#10180e","#1e4a24","#3e8a46","#90d48a","#ffffff"]}}],patterns:{front:["000","041","012",".23"],side:["00","41","12","23"],far:["00","01","12",".2"]},views:{S:{eyes:[["front",-5,0],["front!",3,0]],blush:[[-6,4],[-5,4],[5,4],[6,4]],mouth:[[0,5]],brows:[[-5,-2],[-4,-2],[-3,-1],[5,-2],[4,-2],[3,-1]]},SE:{eyes:[["front",-2,0],["far",5,0]],blush:[[-3,4],[-2,4]],mouth:[[3,5],[4,5]],brows:[[-2,-2],[-1,-2],[0,-1]]},E:{eyes:[["side",4,0]],blush:[[2,4],[3,4]],mouth:[[6,5]],brows:[[4,-2],[5,-2]]}}},s0={id:"face_smile",name:"笑眼",palettes:{eye:["#2a1612","#4a2a20","#7a4a38","#b07a60","#ffffff"],blush:["#a85048","#cc7466","#e08a78","#f0a894","#fcd0c8"]},patterns:{front:[".0.","0.0"],side:["0.",".0"],far:["0","0"]},views:{S:{eyes:[["front",-5,1],["front!",3,1]],blush:[[-6,3],[-5,3],[5,3],[6,3]],mouth:[[-1,4],[0,5],[1,4]],brows:[[-5,-1],[-4,-2],[-3,-2],[5,-1],[4,-2],[3,-2]]},SE:{eyes:[["front",-2,1],["far",5,1]],blush:[[-3,3],[-2,3]],mouth:[[2,4],[3,5],[4,4]],brows:[[-2,-1],[-1,-2],[0,-2]]},E:{eyes:[["side",4,1]],blush:[[2,3],[3,3]],mouth:[[6,4],[5,5]],brows:[[4,-2],[5,-2]]}}},jo=Object.assign({"./bag/satchel.ts":pa,"./bottom/trousers.ts":ua,"./kits/faceKit.ts":ga,"./kits/gearFx.ts":ba,"./kits/hairKit.ts":Ma,"./kits/weaponKit.ts":ya,"./scarf/navy_scarf.ts":Aa,"./shoes/boots.ts":Ia,"./top/armors.ts":qa,"./top/red_cloak.ts":Za,"./top/traveler_jacket.ts":nn,"./weapon/great_swords.ts":yn,"./weapon/hunting_bow.ts":An,"./weapon/short_sword.ts":$n,"./weapon/staff.ts":Xn,"./weapon/starlight_blade.ts":Jn}),Ao=Object.assign({"../../../Sources/Resources/CharacterParts/hair/hair_bun.json":Qn,"../../../Sources/Resources/CharacterParts/hair/hair_long.json":Vn,"../../../Sources/Resources/CharacterParts/hair/hair_messy.json":Zn,"../../../Sources/Resources/CharacterParts/hair/hair_neat.json":t0,"../../../Sources/Resources/CharacterParts/hair/hair_ponytail.json":e0,"../../../Sources/Resources/CharacterParts/hair/hair_side_tail.json":o0,"../../../Sources/Resources/CharacterParts/hair/hair_swept.json":a0,"../../../Sources/Resources/CharacterParts/hair/hair_tied.json":n0}),l0=(Ro=(Lo=Object.values(Object.assign({"../../../Sources/Resources/CharacterParts/hair-colors.json":r0}))[0])==null?void 0:Lo.colors)!=null?Ro:[],So=Object.assign({"../../../Sources/Resources/CharacterParts/face/face_round.json":i0,"../../../Sources/Resources/CharacterParts/face/face_smile.json":s0});function c0(o){return!!o&&typeof o=="object"&&"id"in o&&"slot"in o&&Array.isArray(o.parts)}const ie=new Map;function Me(o,t){ie.has(o.id)&&console.warn(`[items] 重复的装备 id: ${o.id} (${t})`),ie.set(o.id,o)}for(const o of Object.keys(jo).sort())if(!o.startsWith("./kits/"))for(const t of Object.values(jo[o]))c0(t)&&Me(t,o);for(const o of Object.keys(Ao).sort())Me(ho(Ao[o],l0),o);for(const o of Object.keys(So).sort())Me(Je(So[o]),o);
// --- BEGIN PROCEDURAL CHARACTER EXPANSION ---
// Procedural Character Customization Expansion for pixel-baker.js
// Adds:
//   - 20 curated hand-tuned 5-ramp hair colors (shared across ALL 20 hairstyles)
//   - 12 brand-new procedural hairstyles (total 20 hairstyles)
//   - 12 brand-new pure jewel eye colors + 2 heterochromia faces (total 18 eye options)
//   - 3 brand-new procedural bottom styles + expanded trouser/boot colorways
//   - 16 brand-new original non-equipment costumes (时装 — zero in-game armor reuse)
//
// Injected cleanly into pixel-baker.js by native/tools/build_pixel_baker.py.
function registerCharacterExpansion(C) {
  const {
    k, v, ie, Me, ho, Je, ze, We, Ao, i0,
    J, gt, Mt, Pe, ae, uo, ue, ut, wt, Le,
    z, mt, Q, V, _t, Et, pt, ct, xa,
    ma: baseTrousers, Sa: baseBoots
  } = C;

  // =========================================================================
  // 1. 20 CURATED 5-RAMP HAIR COLORS (applied to ALL 8 existing + 12 new)
  // =========================================================================
  const EXPANDED_HAIR_COLORS = [
    { id: "black",    name: "墨黑",   palette: ["#08080e", "#1a1a26", "#30323e", "#52566a", "#9098b0"] },
    { id: "brown",    name: "暖棕",   palette: ["#1c100c", "#4a2a1a", "#7c4a2a", "#b47c42", "#ecc27a"] },
    { id: "chestnut", name: "栗红",   palette: ["#1e0c0a", "#4e1e16", "#86362a", "#c0603e", "#f0a070"] },
    { id: "blonde",   name: "灿金",   palette: ["#4a2c10", "#96641e", "#d4a036", "#f2cc5e", "#fff2ac"] },
    { id: "cream",    name: "奶油金", palette: ["#4c3a24", "#92764c", "#d2b682", "#f2dfae", "#fff8e4"] },
    { id: "caramel",  name: "焦糖橘", palette: ["#381408", "#843412", "#d06020", "#f69844", "#ffda92"] },
    { id: "red",      name: "绯红",   palette: ["#2c080c", "#6c141c", "#b42a2e", "#e45c4e", "#ffa88e"] },
    { id: "wine",     name: "酒红",   palette: ["#220612", "#521028", "#862044", "#ba4668", "#ec8aa4"] },
    { id: "pink",     name: "樱粉",   palette: ["#48162a", "#923a5c", "#d67094", "#f6acc6", "#ffe6f0"] },
    { id: "coral",    name: "珊瑚粉", palette: ["#441816", "#903832", "#d86c58", "#f8a68c", "#ffe2d4"] },
    { id: "violet",   name: "薰衣紫", palette: ["#1c0e32", "#462872", "#764cb4", "#aa82e4", "#e0d0ff"] },
    { id: "lavender", name: "淡丁香", palette: ["#302248", "#6c5492", "#a68ec8", "#d4c2f0", "#f4eeff"] },
    { id: "navy",     name: "靛蓝",   palette: ["#0c1228", "#1e2c5c", "#344e92", "#5a7cc4", "#a2c2f4"] },
    { id: "sky",      name: "天空蓝", palette: ["#102646", "#245e98", "#489edc", "#8cd4fa", "#def6ff"] },
    { id: "teal",     name: "青绿",   palette: ["#0a262a", "#185a5a", "#2c968e", "#68ceb8", "#c0f6e6"] },
    { id: "mint",     name: "薄荷绿", palette: ["#163830", "#3a7a68", "#70bc9c", "#b0e6c6", "#e8fff2"] },
    { id: "emerald",  name: "翡翠绿", palette: ["#0a2212", "#185228", "#2e8842", "#62c06a", "#b4eeaa"] },
    { id: "ash",      name: "雾灰褐", palette: ["#1e1a18", "#483e38", "#786a5e", "#aa9c8c", "#ded4c6"] },
    { id: "silver",   name: "银白",   palette: ["#2e3246", "#6a7088", "#a8b0c2", "#d8dee8", "#ffffff"] },
    { id: "midnight", name: "星夜紫", palette: ["#0c0818", "#20163e", "#3c2c6c", "#6c56a4", "#b4a4e4"] }
  ];

  // Upgrade existing 8 hairstyles so every hairstyle shares all 20 hand-tuned hair colors
  for (const key of Object.keys(Ao).sort()) {
    const def = { ...Ao[key], variants: [] };
    ie.set(def.id, ho(def, EXPANDED_HAIR_COLORS));
  }

  // =========================================================================
  // 2. 12 BRAND-NEW PROCEDURAL HAIRSTYLES (total 20 hairstyles)
  // =========================================================================
  const CLEAN_STYLE = {
    clump: 0.7, global: 0.75, ring: true, streaks: true,
    grit: 0.04, dither: false, closeHoles: true, seamFloor: 1.5, floor: 1, innerLine: 1.25
  };
  const CRISPY_STYLE = {
    clump: 0.7, global: 0.75, ring: false, streaks: true,
    grit: 0.04, dither: false, closeHoles: true, seamFloor: 1.5, floor: 1, innerLine: 1.25
  };

  const NEW_HAIRSTYLES = [
    // 1. 双马尾 — high-perched symmetric twin-tails visible in all 5 views
    {
      id: "hair_twintails",
      name: "双马尾",
      palette: ["#48162a", "#923a5c", "#d67094", "#f6acc6", "#ffe6f0"],
      style: CLEAN_STYLE,
      hairline: [[0, 48], [64, 50], [98, 94], [100, 112], [180, 118]],
      locks: [
        { phi: -46, a1: 64, twist: 14, flick: 1.12, width: 3.2, tip: 0.65 },
        { phi: -18, a1: 66, twist: 10, flick: 1.12, width: 3.4, tip: 0.65 },
        { phi: 12,  a1: 64, twist: -8, flick: 1.12, width: 3.4, tip: 0.65 },
        { phi: 42,  a1: 62, twist: -14, flick: 1.12, width: 3.2, tip: 0.65 },
        { phi: -86, a1: 98, twist: 4, flick: 1.08, width: 3.0, tip: 0.8, taper: 0.7, drop: 5, spread: -0.3 },
        { phi: 86,  a1: 98, twist: -4, flick: 1.08, width: 3.0, tip: 0.8, taper: 0.7, drop: 5, spread: -0.3 },
        { phi: 132, a1: 112, twist: 18, flick: 1.04, width: 4.0, tip: 0.65 },
        { phi: -132, a1: 112, twist: -18, flick: 1.04, width: 4.0, tip: 0.65 },
        { phi: 162, a1: 110, twist: 10, flick: 1.04, width: 4.4, tip: 0.65 },
        { phi: -162, a1: 110, twist: -10, flick: 1.04, width: 4.4, tip: 0.65 },
        // Left & right twin-tail bunches (layered thick tails with playful outward splay)
        { phi: -106, a0: 46, a1: 76, flick: 1.34, lift: 0.16, width: 3.4, taper: 0.84, tip: 0.95, drop: 23, spread: 3.0, twist: -10, tier: 1 },
        { phi: -118, a0: 52, a1: 82, flick: 1.24, lift: 0.12, width: 3.1, taper: 0.82, tip: 0.95, drop: 21, spread: 2.2, twist: -4, tier: 0 },
        { phi: 106,  a0: 46, a1: 76, flick: 1.34, lift: 0.16, width: 3.4, taper: 0.84, tip: 0.95, drop: 23, spread: 3.0, twist: 10, tier: 1 },
        { phi: 118,  a0: 52, a1: 82, flick: 1.24, lift: 0.12, width: 3.1, taper: 0.82, tip: 0.95, drop: 21, spread: 2.2, twist: 4, tier: 0 }
      ]
    },
    // 2. 双丸子头 — two round odango buns perched high on upper sides
    {
      id: "hair_twin_buns",
      name: "双丸子头",
      palette: ["#08080e", "#1a1a26", "#30323e", "#52566a", "#9098b0"],
      style: CLEAN_STYLE,
      hairline: [[0, 48], [62, 50], [98, 92], [100, 110], [180, 116]],
      locks: [
        { phi: -44, a1: 64, twist: 10, flick: 1.12, width: 3.3, tip: 0.65 },
        { phi: -15, a1: 64, twist: 4, flick: 1.12, width: 3.4, tip: 0.65 },
        { phi: 15,  a1: 64, twist: -4, flick: 1.12, width: 3.4, tip: 0.65 },
        { phi: 44,  a1: 64, twist: -10, flick: 1.12, width: 3.3, tip: 0.65 },
        { phi: -92, a1: 96, twist: 4, flick: 1.08, width: 3.0, tip: 0.8, taper: 0.7, drop: 4, spread: -0.3 },
        { phi: 92,  a1: 96, twist: -4, flick: 1.08, width: 3.0, tip: 0.8, taper: 0.7, drop: 4, spread: -0.3 },
        { phi: 132, a1: 112, twist: 14, flick: 1.04, width: 4.2, tip: 0.65 },
        { phi: -132, a1: 112, twist: -14, flick: 1.04, width: 4.2, tip: 0.65 },
        { phi: 164, a1: 110, twist: 6, flick: 1.04, width: 4.4, tip: 0.65 },
        { phi: -164, a1: 110, twist: -6, flick: 1.04, width: 4.4, tip: 0.65 },
        // Left odango bun
        { phi: -96,  a0: 28, a1: 48, flick: 0.90, lift: 0.56, width: 3.3, tier: 1, tip: 1.8, taper: 0.48, twist: 0 },
        { phi: -112, a0: 24, a1: 46, flick: 0.90, lift: 0.58, width: 3.4, tier: 1, tip: 1.8, taper: 0.48, twist: 0 },
        { phi: -128, a0: 28, a1: 48, flick: 0.90, lift: 0.56, width: 3.3, tier: 1, tip: 1.8, taper: 0.48, twist: 0 },
        { phi: -112, a0: 38, a1: 56, flick: 0.90, lift: 0.54, width: 3.2, tier: 1, tip: 1.8, taper: 0.48, twist: 0 },
        // Right odango bun
        { phi: 96,   a0: 28, a1: 48, flick: 0.90, lift: 0.56, width: 3.3, tier: 1, tip: 1.8, taper: 0.48, twist: 0 },
        { phi: 112,  a0: 24, a1: 46, flick: 0.90, lift: 0.58, width: 3.4, tier: 1, tip: 1.8, taper: 0.48, twist: 0 },
        { phi: 128,  a0: 28, a1: 48, flick: 0.90, lift: 0.56, width: 3.3, tier: 1, tip: 1.8, taper: 0.48, twist: 0 },
        { phi: 112,  a0: 38, a1: 56, flick: 0.90, lift: 0.54, width: 3.2, tier: 1, tip: 1.8, taper: 0.48, twist: 0 }
      ]
    },
    // 3. 齐刘海波波头 — classic rounded bob with straight full fringe
    {
      id: "hair_bob_cut",
      name: "齐刘海波波",
      palette: ["#1c100c", "#4a2a1a", "#7c4a2a", "#b47c42", "#ecc27a"],
      style: CLEAN_STYLE,
      hairline: [[0, 56], [68, 56], [96, 98], [96, 118], [180, 124]],
      locks: [
        { phi: -54, a1: 66, twist: -4, flick: 1.04, width: 3.4, tip: 1.2, taper: 0.72 },
        { phi: -26, a1: 65, twist: 0,  flick: 1.04, width: 3.6, tip: 1.3, taper: 0.76 },
        { phi: 0,   a1: 65, twist: 0,  flick: 1.04, width: 3.6, tip: 1.3, taper: 0.76 },
        { phi: 26,  a1: 65, twist: 0,  flick: 1.04, width: 3.6, tip: 1.3, taper: 0.76 },
        { phi: 54,  a1: 66, twist: 4,  flick: 1.04, width: 3.4, tip: 1.2, taper: 0.72 },
        // Rounded jaw-hugging curved bob shell
        { phi: -80,  a1: 108, twist: 8,  flick: 1.02, lift: 0.04, width: 3.5, tip: 1.15, taper: 0.82, drop: 6, spread: -1.4 },
        { phi: 80,   a1: 108, twist: -8, flick: 1.02, lift: 0.04, width: 3.5, tip: 1.15, taper: 0.82, drop: 6, spread: -1.4 },
        { phi: -108, a1: 116, twist: 4,  flick: 1.02, lift: 0.05, width: 3.7, tip: 1.15, taper: 0.82, drop: 7, spread: -1.0 },
        { phi: 108,  a1: 116, twist: -4, flick: 1.02, lift: 0.05, width: 3.7, tip: 1.15, taper: 0.82, drop: 7, spread: -1.0 },
        { phi: -138, a1: 120, twist: 0,  flick: 1.02, lift: 0.04, width: 3.9, tip: 1.15, taper: 0.82, drop: 7, spread: -0.6 },
        { phi: 138,  a1: 120, twist: 0,  flick: 1.02, lift: 0.04, width: 3.9, tip: 1.15, taper: 0.82, drop: 7, spread: -0.6 },
        { phi: 168,  a1: 120, twist: 0,  flick: 1.02, lift: 0.04, width: 4.1, tip: 1.15, taper: 0.82, drop: 7, spread: -0.4 },
        { phi: -168, a1: 120, twist: 0,  flick: 1.02, lift: 0.04, width: 4.1, tip: 1.15, taper: 0.82, drop: 7, spread: -0.4 }
      ]
    },
    // 4. 热血刺猬发 — dynamic anime RPG spiky hair
    {
      id: "hair_spiky",
      name: "热血刺猬发",
      palette: ["#4a2c10", "#96641e", "#d4a036", "#f2cc5e", "#fff2ac"],
      style: CRISPY_STYLE,
      hairline: [[0, 44], [64, 46], [96, 86], [100, 108], [180, 118]],
      locks: [
        { phi: -54, a1: 68, twist: -18, flick: 1.42, width: 3.2, tip: 0.45 },
        { phi: -24, a1: 72, twist: -8,  flick: 1.36, width: 3.2, tip: 0.45 },
        { phi: 4,   a1: 70, twist: 8,   flick: 1.38, width: 3.2, tip: 0.45 },
        { phi: 34,  a1: 68, twist: 18,  flick: 1.44, width: 3.2, tip: 0.45 },
        { phi: 64,  a1: 74, twist: 22,  flick: 1.48, width: 3.0, tip: 0.45 },
        { phi: -96, a1: 98, twist: -10, flick: 1.42, width: 3.2, tip: 0.45 },
        { phi: 96,  a1: 98, twist: 10,  flick: 1.42, width: 3.2, tip: 0.45 },
        { phi: 132, a1: 118, twist: 12, flick: 1.40, width: 3.6, tip: 0.5 },
        { phi: -132, a1: 118, twist: -12, flick: 1.40, width: 3.6, tip: 0.5 },
        { phi: 164, a1: 122, twist: 8,  flick: 1.42, width: 3.8, tip: 0.5 },
        { phi: -164, a1: 122, twist: -8, flick: 1.42, width: 3.8, tip: 0.5 },
        // Bold upper radial hero spikes
        { phi: -155, a0: 4, a1: 42, twist: -16, flick: 1.72, lift: 0.08, width: 3.0, tier: 1, tip: 0.42 },
        { phi: -95,  a0: 4, a1: 40, twist: -18, flick: 1.70, lift: 0.08, width: 2.9, tier: 1, tip: 0.42 },
        { phi: -35,  a0: 4, a1: 38, twist: -14, flick: 1.74, lift: 0.10, width: 2.8, tier: 1, tip: 0.42 },
        { phi: 25,   a0: 4, a1: 38, twist: 16,  flick: 1.74, lift: 0.10, width: 2.8, tier: 1, tip: 0.42 },
        { phi: 90,   a0: 4, a1: 40, twist: 18,  flick: 1.70, lift: 0.08, width: 2.9, tier: 1, tip: 0.42 },
        { phi: 150,  a0: 4, a1: 42, twist: 16,  flick: 1.72, lift: 0.08, width: 3.0, tier: 1, tip: 0.42 }
      ]
    },
    // 5. 狼尾层次发 — shaggy layered wolf-cut / mullet with flared nape
    {
      id: "hair_wolf_cut",
      name: "狼尾层次发",
      palette: ["#0c1228", "#1e2c5c", "#344e92", "#5a7cc4", "#a2c2f4"],
      style: CRISPY_STYLE,
      hairline: [[0, 48], [66, 50], [98, 96], [100, 118], [180, 130]],
      locks: [
        { phi: -56, a1: 72, twist: 16, flick: 1.24, width: 3.1, tip: 0.55 },
        { phi: -28, a1: 76, twist: 18, flick: 1.22, width: 3.3, tip: 0.55 },
        { phi: 0,   a1: 72, twist: 14, flick: 1.22, width: 3.2, tip: 0.55 },
        { phi: 28,  a1: 74, twist: -10, flick: 1.22, width: 3.2, tip: 0.55 },
        { phi: 56,  a1: 70, twist: -16, flick: 1.24, width: 3.1, tip: 0.55 },
        // Cheek-skimming feathered side locks
        { phi: -88, a1: 106, twist: -6, flick: 1.22, width: 3.0, tip: 0.6, taper: 0.72, drop: 5, spread: 0.9 },
        { phi: 88,  a1: 106, twist: 6,  flick: 1.22, width: 3.0, tip: 0.6, taper: 0.72, drop: 5, spread: 0.9 },
        // Shaggy flared wolf-tail nape strands
        { phi: -116, a1: 118, twist: -10, flick: 1.28, width: 3.1, tip: 0.55, taper: 0.72, drop: 9, spread: 2.2 },
        { phi: 116,  a1: 118, twist: 10,  flick: 1.28, width: 3.1, tip: 0.55, taper: 0.72, drop: 9, spread: 2.2 },
        { phi: -144, a1: 122, twist: -8,  flick: 1.26, width: 3.3, tip: 0.55, taper: 0.74, drop: 11, spread: 1.6 },
        { phi: 144,  a1: 122, twist: 8,   flick: 1.26, width: 3.3, tip: 0.55, taper: 0.74, drop: 11, spread: 1.6 },
        { phi: 170,  a1: 124, twist: 6,   flick: 1.26, width: 3.4, tip: 0.55, taper: 0.74, drop: 12, spread: 1.0 },
        { phi: -170, a1: 124, twist: -6,  flick: 1.26, width: 3.4, tip: 0.55, taper: 0.74, drop: 12, spread: 1.0 },
        // Crown layered feather spikes
        { phi: -120, a0: 3, a1: 42, twist: 18, flick: 1.48, lift: 0.05, width: 2.8, tier: 1, tip: 0.5 },
        { phi: -45,  a0: 3, a1: 38, twist: 20, flick: 1.46, lift: 0.05, width: 2.6, tier: 1, tip: 0.5 },
        { phi: 50,   a0: 3, a1: 38, twist: -18, flick: 1.46, lift: 0.05, width: 2.6, tier: 1, tip: 0.5 },
        { phi: 130,  a0: 3, a1: 42, twist: -16, flick: 1.48, lift: 0.05, width: 2.8, tier: 1, tip: 0.5 }
      ]
    },
    // 6. 公主切长直发 — straight blunt bangs + sharp cheek locks + waist-length back veil
    {
      id: "hair_hime_cut",
      name: "公主切长发",
      palette: ["#0c0818", "#20163e", "#3c2c6c", "#6c56a4", "#b4a4e4"],
      style: CLEAN_STYLE,
      hairline: [[0, 54], [68, 54], [94, 98], [94, 120], [180, 128]],
      locks: [
        // Crisp blunt fringe
        { phi: -48, a1: 64, twist: 0, flick: 1.04, width: 3.4, tip: 1.3, taper: 0.78 },
        { phi: -24, a1: 64, twist: 0, flick: 1.04, width: 3.5, tip: 1.3, taper: 0.78 },
        { phi: 0,   a1: 64, twist: 0, flick: 1.04, width: 3.5, tip: 1.3, taper: 0.78 },
        { phi: 24,  a1: 64, twist: 0, flick: 1.04, width: 3.5, tip: 1.3, taper: 0.78 },
        { phi: 48,  a1: 64, twist: 0, flick: 1.04, width: 3.4, tip: 1.3, taper: 0.78 },
        // Iconic sharp straight cheek-level hime side-locks
        { phi: -74, a1: 96, twist: 0, flick: 1.04, width: 3.0, tip: 1.4, taper: 0.86, drop: 6, spread: -0.2 },
        { phi: 74,  a1: 96, twist: 0, flick: 1.04, width: 3.0, tip: 1.4, taper: 0.86, drop: 6, spread: -0.2 },
        // Long straight flowing back curtain
        { phi: -102, a1: 108, twist: 0, flick: 1.02, width: 3.2, tip: 1.1, taper: 0.86, drop: 19, spread: 0.0 },
        { phi: 102,  a1: 108, twist: 0, flick: 1.02, width: 3.2, tip: 1.1, taper: 0.86, drop: 19, spread: 0.0 },
        { phi: -126, a1: 114, twist: 0, flick: 1.02, width: 3.4, tip: 1.1, taper: 0.86, drop: 21, spread: 0.0 },
        { phi: 126,  a1: 114, twist: 0, flick: 1.02, width: 3.4, tip: 1.1, taper: 0.86, drop: 21, spread: 0.0 },
        { phi: -152, a1: 118, twist: 0, flick: 1.02, width: 3.6, tip: 1.1, taper: 0.86, drop: 22, spread: 0.0 },
        { phi: 152,  a1: 118, twist: 0, flick: 1.02, width: 3.6, tip: 1.1, taper: 0.86, drop: 22, spread: 0.0 },
        { phi: 174,  a1: 118, twist: 0, flick: 1.02, width: 3.6, tip: 1.1, taper: 0.86, drop: 22, spread: 0.0 },
        { phi: -174, a1: 118, twist: 0, flick: 1.02, width: 3.6, tip: 1.1, taper: 0.86, drop: 22, spread: 0.0 }
      ]
    },
    // 7. 浪漫波浪长发 — voluminous flowing wavy long hair
    {
      id: "hair_wavy_long",
      name: "浪漫大波浪",
      palette: ["#381408", "#843412", "#d06020", "#f69844", "#ffda92"],
      style: CLEAN_STYLE,
      hairline: [[0, 48], [64, 50], [94, 96], [96, 118], [180, 128]],
      locks: [
        { phi: -50, a1: 68, twist: -18, flick: 1.18, lift: 0.06, width: 3.4, tip: 0.75 },
        { phi: -22, a1: 66, twist: -14, flick: 1.16, lift: 0.06, width: 3.4, tip: 0.75 },
        { phi: 12,  a1: 68, twist: 16,  flick: 1.18, lift: 0.06, width: 3.5, tip: 0.75 },
        { phi: 44,  a1: 66, twist: 18,  flick: 1.18, lift: 0.06, width: 3.4, tip: 0.75 },
        // Wide billowing wavy cascading locks
        { phi: -82,  a1: 102, twist: -12, flick: 1.18, lift: 0.08, width: 3.4, tip: 0.9, taper: 0.84, drop: 14, spread: 2.2 },
        { phi: 82,   a1: 102, twist: 12,  flick: 1.18, lift: 0.08, width: 3.4, tip: 0.9, taper: 0.84, drop: 14, spread: 2.2 },
        { phi: -108, a1: 110, twist: 10,  flick: 1.16, lift: 0.10, width: 3.6, tip: 0.9, taper: 0.84, drop: 18, spread: 3.0 },
        { phi: 108,  a1: 110, twist: -10, flick: 1.16, lift: 0.10, width: 3.6, tip: 0.9, taper: 0.84, drop: 18, spread: 3.0 },
        { phi: -136, a1: 116, twist: -8,  flick: 1.14, lift: 0.08, width: 3.8, tip: 0.9, taper: 0.84, drop: 19, spread: 2.2 },
        { phi: 136,  a1: 116, twist: 8,   flick: 1.14, lift: 0.08, width: 3.8, tip: 0.9, taper: 0.84, drop: 19, spread: 2.2 },
        { phi: -164, a1: 118, twist: 6,   flick: 1.12, lift: 0.08, width: 3.8, tip: 0.9, taper: 0.84, drop: 20, spread: 1.2 },
        { phi: 164,  a1: 118, twist: -6,  flick: 1.12, lift: 0.08, width: 3.8, tip: 0.9, taper: 0.84, drop: 20, spread: 1.2 },
        // Fluffy crown waves
        { phi: -135, a0: 4, a1: 42, twist: 24, flick: 1.24, lift: 0.10, width: 3.2, tier: 1, tip: 0.8 },
        { phi: -55,  a0: 4, a1: 38, twist: 22, flick: 1.22, lift: 0.10, width: 3.0, tier: 1, tip: 0.8 },
        { phi: 55,   a0: 4, a1: 38, twist: -22, flick: 1.22, lift: 0.10, width: 3.0, tier: 1, tip: 0.8 },
        { phi: 135,  a0: 4, a1: 42, twist: -24, flick: 1.24, lift: 0.10, width: 3.2, tier: 1, tip: 0.8 }
      ]
    },
    // 8. 半扎公主头 — gathered top-back half-bun + flowing shoulder hair
    {
      id: "hair_half_up",
      name: "半扎公主头",
      palette: ["#4c3a24", "#92764c", "#d2b682", "#f2dfae", "#fff8e4"],
      style: CLEAN_STYLE,
      hairline: [[0, 48], [64, 50], [96, 94], [98, 116], [180, 126]],
      locks: [
        { phi: -44, a1: 64, twist: 18, flick: 1.12, width: 3.2, tip: 0.65 },
        { phi: -16, a1: 64, twist: 20, flick: 1.12, width: 3.4, tip: 0.65 },
        { phi: 14,  a1: 62, twist: 18, flick: 1.12, width: 3.2, tip: 0.65 },
        { phi: 44,  a1: 62, twist: -14, flick: 1.12, width: 3.2, tip: 0.65 },
        // Flowing lower shoulder locks
        { phi: -86,  a1: 102, twist: 4,  flick: 1.06, width: 2.9, tip: 0.85, taper: 0.78, drop: 10, spread: -0.2 },
        { phi: 86,   a1: 102, twist: -4, flick: 1.06, width: 2.9, tip: 0.85, taper: 0.78, drop: 10, spread: -0.2 },
        { phi: -116, a1: 112, twist: 0,  flick: 1.06, width: 3.2, tip: 0.85, taper: 0.80, drop: 14, spread: 0.2 },
        { phi: 116,  a1: 112, twist: 0,  flick: 1.06, width: 3.2, tip: 0.85, taper: 0.80, drop: 14, spread: 0.2 },
        { phi: -146, a1: 116, twist: 0,  flick: 1.06, width: 3.4, tip: 0.85, taper: 0.80, drop: 15, spread: 0.2 },
        { phi: 146,  a1: 116, twist: 0,  flick: 1.06, width: 3.4, tip: 0.85, taper: 0.80, drop: 15, spread: 0.2 },
        { phi: 170,  a1: 118, twist: 0,  flick: 1.06, width: 3.4, tip: 0.85, taper: 0.80, drop: 15, spread: 0.0 },
        { phi: -170, a1: 118, twist: 0,  flick: 1.06, width: 3.4, tip: 0.85, taper: 0.80, drop: 15, spread: 0.0 },
        // Gathered half-up knot / mini-bun on upper back + short ribbon cascade
        { phi: 155,  a0: 36, a1: 56, flick: 0.94, lift: 0.44, width: 3.1, tier: 1, tip: 1.6, taper: 0.46, twist: 0 },
        { phi: -155, a0: 36, a1: 56, flick: 0.94, lift: 0.44, width: 3.1, tier: 1, tip: 1.6, taper: 0.46, twist: 0 },
        { phi: 180,  a0: 34, a1: 58, flick: 0.94, lift: 0.48, width: 3.3, tier: 1, tip: 1.6, taper: 0.46, twist: 0 },
        { phi: 180,  a0: 54, a1: 72, flick: 1.24, lift: 0.16, width: 2.8, taper: 0.72, tip: 0.9, drop: 11, spread: 0.4, twist: 0 }
      ]
    },
    // 9. 中分括号发 — stylish center-parted curtain bangs
    {
      id: "hair_curtain",
      name: "中分括号发",
      palette: ["#1e1a18", "#483e38", "#786a5e", "#aa9c8c", "#ded4c6"],
      style: CLEAN_STYLE,
      hairline: [[0, 38], [24, 46], [68, 54], [98, 94], [100, 114], [180, 122]],
      locks: [
        // Symmetrical outward-swept curtain bangs leaving clean center part
        { phi: -16, a0: 10, a1: 76, twist: -34, flick: 1.14, lift: 0.04, width: 3.4, tip: 0.65 },
        { phi: -44, a0: 10, a1: 82, twist: -22, flick: 1.12, lift: 0.04, width: 3.4, tip: 0.65 },
        { phi: 16,  a0: 10, a1: 76, twist: 34,  flick: 1.14, lift: 0.04, width: 3.4, tip: 0.65 },
        { phi: 44,  a0: 10, a1: 82, twist: 22,  flick: 1.12, lift: 0.04, width: 3.4, tip: 0.65 },
        // Soft layered sides & back
        { phi: -86,  a1: 106, twist: -8, flick: 1.08, width: 3.3, tip: 0.7, drop: 2, spread: -0.4 },
        { phi: 86,   a1: 106, twist: 8,  flick: 1.08, width: 3.3, tip: 0.7, drop: 2, spread: -0.4 },
        { phi: -120, a1: 118, twist: -4, flick: 1.06, width: 3.8, tip: 0.7 },
        { phi: 120,  a1: 118, twist: 4,  flick: 1.06, width: 3.8, tip: 0.7 },
        { phi: -154, a1: 120, twist: 0,  flick: 1.06, width: 4.0, tip: 0.7 },
        { phi: 154,  a1: 120, twist: 0,  flick: 1.06, width: 4.0, tip: 0.7 },
        { phi: 180,  a1: 120, twist: 0,  flick: 1.06, width: 4.0, tip: 0.7 },
        // Lifted center-part volume
        { phi: -28, a0: 4, a1: 38, twist: -28, flick: 1.24, lift: 0.08, width: 3.0, tier: 1, tip: 0.7 },
        { phi: 28,  a0: 4, a1: 38, twist: 28,  flick: 1.24, lift: 0.08, width: 3.0, tier: 1, tip: 0.7 }
      ]
    },
    // 10. 蓬松羊毛卷 — adorable bouncy fluffy curly cloud dome
    {
      id: "hair_fluffy_curl",
      name: "蓬松羊毛卷",
      palette: ["#1c100c", "#4a2a1a", "#7c4a2a", "#b47c42", "#ecc27a"],
      style: { ...CLEAN_STYLE, ring: false, grit: 0.08 },
      hairline: [[0, 48], [64, 52], [96, 98], [100, 118], [180, 124]],
      locks: [
        // Curly bangs + fluffy rounded dome (taller crown, snugger cheek curls)
        { phi: -44, a0: 14, a1: 64, twist: -14, flick: 1.12, lift: 0.12, width: 3.8, tip: 1.5, taper: 0.58 },
        { phi: -16, a0: 12, a1: 64, twist: 12,  flick: 1.12, lift: 0.14, width: 3.9, tip: 1.5, taper: 0.58 },
        { phi: 16,  a0: 12, a1: 64, twist: -12, flick: 1.12, lift: 0.14, width: 3.9, tip: 1.5, taper: 0.58 },
        { phi: 44,  a0: 14, a1: 64, twist: 14,  flick: 1.12, lift: 0.12, width: 3.8, tip: 1.5, taper: 0.58 },
        { phi: -80, a0: 18, a1: 102, twist: -12, flick: 1.10, lift: 0.10, width: 3.8, tip: 1.4, taper: 0.65, drop: 4, spread: -0.4 },
        { phi: 80,  a0: 18, a1: 102, twist: 12,  flick: 1.10, lift: 0.10, width: 3.8, tip: 1.4, taper: 0.65, drop: 4, spread: -0.4 },
        { phi: -112, a0: 18, a1: 114, twist: 10,  flick: 1.12, lift: 0.12, width: 4.0, tip: 1.4, taper: 0.65, drop: 5, spread: 0.0 },
        { phi: 112,  a0: 18, a1: 114, twist: -10, flick: 1.12, lift: 0.12, width: 4.0, tip: 1.4, taper: 0.65, drop: 5, spread: 0.0 },
        { phi: -148, a0: 18, a1: 118, twist: -10, flick: 1.12, lift: 0.12, width: 4.1, tip: 1.4, taper: 0.65, drop: 5, spread: 0.0 },
        { phi: 148,  a0: 18, a1: 118, twist: 10,  flick: 1.12, lift: 0.12, width: 4.1, tip: 1.4, taper: 0.65, drop: 5, spread: 0.0 },
        { phi: 180,  a0: 18, a1: 120, twist: 0,   flick: 1.12, lift: 0.12, width: 4.2, tip: 1.4, taper: 0.65, drop: 5, spread: 0.0 },
        // Rounded fluffy top crown curls (gives soft spherical curly volume!)
        { phi: -135, a0: 4, a1: 36, twist: 16,  flick: 1.14, lift: 0.24, width: 3.8, tier: 1, tip: 1.6, taper: 0.5 },
        { phi: -55,  a0: 4, a1: 34, twist: -16, flick: 1.14, lift: 0.24, width: 3.8, tier: 1, tip: 1.6, taper: 0.5 },
        { phi: 0,    a0: 2, a1: 30, twist: 10,  flick: 1.14, lift: 0.26, width: 3.8, tier: 1, tip: 1.6, taper: 0.5 },
        { phi: 55,   a0: 4, a1: 34, twist: 16,  flick: 1.14, lift: 0.24, width: 3.8, tier: 1, tip: 1.6, taper: 0.5 },
        { phi: 135,  a0: 4, a1: 36, twist: -16, flick: 1.14, lift: 0.24, width: 3.8, tier: 1, tip: 1.6, taper: 0.5 }
      ]
    },
    // 11. 侧麻花辫 — gentle swept bangs + thick woven side braid cascading over shoulder
    {
      id: "hair_side_braid",
      name: "侧麻花辫",
      palette: ["#1e0c0a", "#4e1e16", "#86362a", "#c0603e", "#f0a070"],
      style: CLEAN_STYLE,
      hairline: [[0, 48], [62, 50], [98, 94], [100, 114], [180, 120]],
      locks: [
        { phi: -44, a1: 66, twist: 24, flick: 1.12, width: 3.3, tip: 0.65 },
        { phi: -14, a1: 64, twist: 26, flick: 1.12, width: 3.4, tip: 0.65 },
        { phi: 18,  a1: 60, twist: 24, flick: 1.12, width: 3.2, tip: 0.65 },
        { phi: 52,  a1: 70, twist: 40, flick: 1.06, width: 3.4, tip: 0.65 },
        { phi: -86, a1: 100, twist: 6, flick: 1.08, width: 3.1, tip: 0.8, taper: 0.72, drop: 5, spread: -0.2 },
        { phi: 92,  a1: 98, twist: -6, flick: 1.08, width: 3.1, tip: 0.8, taper: 0.72, drop: 4, spread: -0.2 },
        { phi: 130, a1: 114, twist: 22, flick: 1.04, width: 4.2, tip: 0.65 },
        { phi: -130, a1: 114, twist: -22, flick: 1.04, width: 4.2, tip: 0.65 },
        { phi: 164, a1: 112, twist: 10, flick: 1.04, width: 4.4, tip: 0.65 },
        { phi: -164, a1: 112, twist: -10, flick: 1.04, width: 4.4, tip: 0.65 }
      ]
    },
    // 12. 飒爽背头 — confident open-forehead swept-back quiff/pompadour
    {
      id: "hair_quiff",
      name: "飒爽背头",
      palette: ["#2e3246", "#6a7088", "#a8b0c2", "#d8dee8", "#ffffff"],
      style: CRISPY_STYLE,
      hairline: [[0, 32], [44, 38], [86, 78], [100, 102], [180, 114]],
      locks: [
        // Swept-back forehead crest waves
        { phi: -30, a0: 14, a1: 52, twist: -22, flick: 1.24, lift: 0.16, width: 3.4, tier: 1, tip: 0.65 },
        { phi: 0,   a0: 12, a1: 50, twist: 14,  flick: 1.28, lift: 0.20, width: 3.6, tier: 1, tip: 0.65 },
        { phi: 30,  a0: 14, a1: 52, twist: 26,  flick: 1.24, lift: 0.16, width: 3.4, tier: 1, tip: 0.65 },
        // Sleek tapered sides swept backward
        { phi: -78,  a0: 16, a1: 86, twist: -26, flick: 1.06, width: 3.1, tip: 0.65 },
        { phi: 78,   a0: 16, a1: 86, twist: 26,  flick: 1.06, width: 3.1, tip: 0.65 },
        { phi: -116, a0: 12, a1: 110, twist: -14, flick: 1.06, width: 3.7, tip: 0.65 },
        { phi: 116,  a0: 12, a1: 110, twist: 14,  flick: 1.06, width: 3.7, tip: 0.65 },
        { phi: -150, a0: 10, a1: 114, twist: -6,  flick: 1.06, width: 4.0, tip: 0.65 },
        { phi: 150,  a0: 10, a1: 114, twist: 6,   flick: 1.06, width: 4.0, tip: 0.65 },
        { phi: 180,  a0: 10, a1: 116, twist: 0,   flick: 1.06, width: 4.0, tip: 0.65 },
        // Slicked-back crown ridge
        { phi: 180,  a0: 2, a1: 42, twist: 0, flick: 1.26, lift: 0.12, width: 3.4, tier: 1, tip: 0.6 }
      ]
    }
  ];

  // Register the 12 new hairstyles with all 20 hair colors
  for (const def of NEW_HAIRSTYLES) {
    const item = ho(def, EXPANDED_HAIR_COLORS);

    // Add real woven braided plait over one shoulder for hair_side_braid!
    if (def.id === "hair_side_braid") {
      const braidTie = k("braid-gold-tie", "#3e2408", "#8a5c16", "#d8a430", "#f6d86c", "#fff6c0");
      item.palettes.tie = braidTie;
      const drawBraid = (ctx, targetLayer) => {
        const { g, pose } = ctx;
        const cx = pose.head.x + pose.sin * 0.2;
        const cy = pose.head.y - 1.2;
        // Anchor behind left ear (phi = -104, a = 104)
        const root = xa(pose, cx, cy, 102, -102, 1.04);
        const inFront = root.near >= -0.22;
        if ((targetLayer === "hair") !== inFront) return;
        const sway = pose.anim === "walk" ? Math.sin(pose.phase * 2) * 1.1 : 0;
        const driftX = (root.x < cx ? -1.4 : 1.0) + pose.sin * 0.6;
        ctx.pal("main");
        g.grit = 0.04;
        g.dither = false;
        g.anchor(root.x, root.y);
        // 5 overlapping woven braid beads descending cleanly over shoulder
        const segs = 5;
        let lastX = root.x, lastY = root.y;
        for (let s = 0; s < segs; s++) {
          const t = (s + 0.5) / segs;
          const bx = root.x + driftX * t + sway * t * t + (s % 2 === 0 ? -0.55 : 0.55);
          const by = root.y + 3.2 * (s + 0.65);
          const rx = 2.15 - t * 0.45;
          const ry = 2.0 - t * 0.25;
          g.ellipse(bx, by, rx, ry, (shade, lx, ly) => {
            const twist = (s % 2 === 0 ? 1 : -1) * lx * 0.45;
            return Math.min(4, Math.max(1, g.t(shade * 0.9 + twist, 0.15)));
          });
          lastX = bx;
          lastY = by;
        }
        // Tapered hair tassel tip below the tie
        g.capsule(lastX, lastY + 1.8, lastX + sway * 0.4, lastY + 5.2, 1.5, 0.45, s => Math.max(1, g.t(s, 0.05)));
        // Tiny golden ribbon band tying the braid
        ctx.pal("tie");
        g.ellipse(lastX, lastY + 1.7, 1.5, 0.95, s => s > 0.2 ? 4 : 2);
      };
      item.parts.push({ layer: "cape", innerLine: 1.25, draw: ctx => drawBraid(ctx, "cape") });
      item.parts.push({ layer: "hair", innerLine: 1.25, draw: ctx => drawBraid(ctx, "hair") });
    }

    // Add tiny pearl/gold hair-tie accents at the base of twin-tails & twin-buns for extra charm
    if (def.id === "hair_twintails") {
      const ribbonPal = k("twintail-ribbon", "#3e2408", "#8a5c16", "#d8a430", "#f6d86c", "#fff6c0");
      item.palettes.tie = ribbonPal;
      const drawTies = (ctx, frontPass) => {
        const { g, pose } = ctx;
        const cx = pose.head.x + pose.sin * 0.2;
        const cy = pose.head.y - 1.2;
        ctx.pal("tie");
        g.grit = 0;
        for (const phi of [-106, 106]) {
          const p = xa(pose, cx, cy, 62, phi, 1.12);
          const isFront = p.near >= -0.15;
          if (isFront !== frontPass) continue;
          g.ellipse(p.x, p.y, 1.55, 1.1, s => s > 0.2 ? 4 : 3);
        }
      };
      item.parts.push({ layer: "hair_back", outline: false, draw: ctx => drawTies(ctx, false) });
      item.parts.push({ layer: "hair", outline: false, draw: ctx => drawTies(ctx, true) });
    }

    Me(item, "expansion/hair/" + def.id);
  }

  // =========================================================================
  // 3. 18 EYE COLORS (16 pure jewel eyes on face_round + 2 heterochromia faces)
  // =========================================================================
  const EXPANDED_EYE_VARIANTS = [
    { id: "teal",     name: "碧青瞳",   palettes: { eye: ["#17101e", "#1e3a5c", "#3e9aa8", "#8ad8d8", "#ffffff"] } },
    { id: "amber",    name: "琥珀瞳",   palettes: { eye: ["#1e120a", "#5a3410", "#c07a20", "#f0c060", "#ffffff"] } },
    { id: "violet",   name: "紫晶瞳",   palettes: { eye: ["#160e22", "#3a2266", "#7a52c0", "#c0a0f0", "#ffffff"] } },
    { id: "blue",     name: "蔚蓝瞳",   palettes: { eye: ["#14101e", "#1c2e6a", "#3a64c4", "#86b4f4", "#ffffff"] } },
    { id: "green",    name: "翠绿瞳",   palettes: { eye: ["#10180e", "#1e4a24", "#3e8a46", "#90d48a", "#ffffff"] } },
    { id: "ruby",     name: "绯红瞳",   palettes: { eye: ["#22060c", "#6c1020", "#cc2a3c", "#ff848e", "#ffffff"] } },
    { id: "sakura",   name: "樱粉瞳",   palettes: { eye: ["#2a0c1c", "#7c2650", "#dc6296", "#ffb2d4", "#ffffff"] } },
    { id: "gold",     name: "琉璃金瞳", palettes: { eye: ["#241604", "#744c0c", "#dca420", "#ffe478", "#ffffff"] } },
    { id: "ice",      name: "冰晶蓝瞳", palettes: { eye: ["#101e30", "#2c6496", "#6ec4ee", "#c6f2ff", "#ffffff"] } },
    { id: "obsidian", name: "墨玉瞳",   palettes: { eye: ["#08080e", "#1e2030", "#424864", "#8a94b4", "#ffffff"] } },
    { id: "hazel",    name: "栗棕瞳",   palettes: { eye: ["#1e1008", "#542c14", "#985828", "#d89c60", "#ffffff"] } },
    { id: "emerald",  name: "森翡翠瞳", palettes: { eye: ["#081e12", "#145c34", "#28b464", "#86f2aa", "#ffffff"] } },
    { id: "orange",   name: "落日橙瞳", palettes: { eye: ["#280e04", "#7e300c", "#e46e22", "#ffba6c", "#ffffff"] } },
    { id: "silver",   name: "银月瞳",   palettes: { eye: ["#181c28", "#485068", "#8e98b2", "#d4dce8", "#ffffff"] } },
    { id: "indigo",   name: "星海蓝瞳", palettes: { eye: ["#0c0c24", "#20246e", "#4454c8", "#98a8ff", "#ffffff"] } },
    { id: "magenta",  name: "莓果洋红", palettes: { eye: ["#240620", "#6c145e", "#c430a4", "#f890e2", "#ffffff"] } }
  ];

  // Replace face_round with all 16 pure jewel eye variants
  ie.set("face_round", Je({ ...i0, variants: EXPANDED_EYE_VARIANTS }));

  // Helper for heterochromia (异色瞳) faces using exact face_round geometry
  function makeHeteroFace(id, name, leftEyeHexes, rightEyeHexes) {
    const palettes = {
      eyeL: k(`${id}-eyeL`, ...leftEyeHexes),
      eyeR: k(`${id}-eyeR`, ...rightEyeHexes),
      blush: k(`${id}-blush`, ...i0.palettes.blush)
    };
    return {
      id,
      name,
      slot: "face",
      palettes,
      variants: [],
      parts: [{
        layer: "head",
        mask: "below",
        outline: false,
        draw: ctx => {
          const view = i0.views[ctx.dir];
          if (!view) return;
          const { g } = ctx;
          const { px, py, k: step } = ze(ctx);
          const dot = (d, val) => g.cellsPx([String(val)], px + d[0] * step, py + d[1] * step);
          (view.eyes || []).forEach(([patName, ox, oy], idx) => {
            ctx.pal(idx === 0 ? "eyeL" : "eyeR");
            const mirrored = patName.endsWith("!");
            const pat = i0.patterns[mirrored ? patName.slice(0, -1) : patName];
            g.cellsPx(mirrored ? We(pat) : pat, px + ox * step, py + oy * step);
          });
          ctx.pal("blush");
          for (const d of view.blush || []) dot(d, 2);
          ctx.pal("skin");
          for (const d of view.mouth || []) dot(d, 1);
          for (const d of view.brows || []) dot(d, 1);
        }
      }]
    };
  }

  Me(
    makeHeteroFace(
      "face_hetero_gold_blue", "金蓝异瞳",
      ["#241604", "#744c0c", "#dca420", "#ffe478", "#ffffff"],
      ["#14101e", "#1c2e6a", "#3a64c4", "#86b4f4", "#ffffff"]
    ),
    "expansion/face/hetero_gold_blue"
  );
  Me(
    makeHeteroFace(
      "face_hetero_crimson_cyan", "绯青异瞳",
      ["#22060c", "#6c1020", "#cc2a3c", "#ff848e", "#ffffff"],
      ["#101e30", "#2c6496", "#6ec4ee", "#c6f2ff", "#ffffff"]
    ),
    "expansion/face/hetero_crimson_cyan"
  );

  // =========================================================================
  // 4. EXPANDED BOTTOMS & SHOES (coordinated with costumes + usable in Lab)
  // =========================================================================
  const EXTRA_TROUSER_VARIANTS = [
    { id: "navy",    name: "学院藏蓝", palettes: { main: k("tr-navy",    "#0a0e20", "#182448", "#2a3e72", "#46609c", "#7492cc") } },
    { id: "denim",   name: "丹宁蓝",   palettes: { main: k("tr-denim",   "#0e1828", "#223c60", "#3a6294", "#628ec0", "#9cc2e8") } },
    { id: "khaki",   name: "卡其沙",   palettes: { main: k("tr-khaki",   "#241a0e", "#5a462c", "#90744e", "#bea278", "#e6d2ae") } },
    { id: "slate",   name: "学院灰",   palettes: { main: k("tr-slate",   "#12141c", "#2c303e", "#4e5468", "#788098", "#aeb6cc") } },
    { id: "black",   name: "曜石黑",   palettes: { main: k("tr-black",   "#06060a", "#14141c", "#242632", "#3e4254", "#666c82") } },
    { id: "indigo",  name: "星夜靛",   palettes: { main: k("tr-indigo",  "#0a081e", "#1c1848", "#302a74", "#5048a6", "#847cd6") } },
    { id: "crimson", name: "酒红",     palettes: { main: k("tr-crimson", "#20060c", "#4e101c", "#822030", "#b24250", "#e27a84") } },
    { id: "forest",  name: "森绿",     palettes: { main: k("tr-forest",  "#0a1810", "#183c24", "#2c643e", "#4e925e", "#82c48c") } }
  ];
  for (const variant of EXTRA_TROUSER_VARIANTS) {
    if (!baseTrousers.variants.some(x => x.id === variant.id)) baseTrousers.variants.push(variant);
  }

  const EXTRA_BOOT_VARIANTS = [
    { id: "white",   name: "雪白",   palettes: { main: k("bt-white",   "#303444", "#767c90", "#b8bcc8", "#e6e8ee", "#ffffff") } },
    { id: "cream",   name: "暖米",   palettes: { main: k("bt-cream",   "#3a2c1c", "#806648", "#bca27e", "#e4d0ae", "#fff4dc") } },
    { id: "navy",    name: "藏蓝",   palettes: { main: k("bt-navy",    "#080c1c", "#16244a", "#284078", "#4866a6", "#80a0da") } },
    { id: "crimson", name: "酒红",   palettes: { main: k("bt-crimson", "#24060c", "#58121e", "#942434", "#c84c58", "#f68c94") } },
    { id: "tan",     name: "浅驼",   palettes: { main: k("bt-tan",     "#26160a", "#603a1c", "#9c6638", "#ce965e", "#f6cc96") } }
  ];
  for (const variant of EXTRA_BOOT_VARIANTS) {
    if (!baseBoots.variants.some(x => x.id === variant.id)) baseBoots.variants.push(variant);
  }

  // Brand-new procedural bottom: Pleated Skirt + Knee Socks
  const skirtNavy = k("skirt-navy", "#080e22", "#162652", "#264084", "#4666b4", "#7ea2e6");
  const sockWhite = k("sock-white", "#34384a", "#7e8498", "#c2c6d2", "#eceef4", "#ffffff");
  const drawSockLeg = idx => ({
    layer: "bottom",
    draw: ctx => {
      const { g } = ctx;
      const leg = ctx.pose.legs[idx];
      const shade = ut(ctx, leg.foot);
      const fx = leg.foot.x, fy = leg.foot.y - 5;
      ctx.pal("sock");
      g.anchor(fx, fy);
      g.capsule(leg.knee.x, leg.knee.y, fx, fy, 1.9, 1.8, c => g.t(c, shade + 0.1));
    }
  });
  const pleatedSkirt = {
    id: "bottom_pleated_skirt",
    name: "百褶裙配长袜",
    slot: "bottom",
    palettes: { main: skirtNavy, trim: sockWhite, sock: sockWhite },
    variants: [
      { id: "navy",    name: "藏蓝", palettes: { main: skirtNavy } },
      { id: "crimson", name: "格纹红", palettes: { main: k("skirt-crimson", "#260812", "#621426", "#a2263c", "#d45064", "#fa94a2") } },
      { id: "violet",  name: "星梦紫", palettes: { main: k("skirt-violet",  "#1c0e34", "#482876", "#784cb8", "#aa82e6", "#dfd0ff") } },
      { id: "gold",    name: "向日葵", palettes: { main: k("skirt-gold",    "#3c2208", "#8c5a14", "#d69a28", "#f6cb5a", "#fff2aa") } },
      { id: "slate",   name: "学院灰", palettes: { main: k("skirt-slate",   "#161822", "#343a4c", "#5a6278", "#8892aa", "#c0c8dc") } }
    ],
    parts: [
      drawSockLeg(0),
      drawSockLeg(1),
      {
        layer: "bottom",
        draw: ctx => {
          const { g, pose } = ctx;
          const sway = pose.anim === "walk" ? Math.sin(pose.phase) * 0.7 : 0;
          const hipY = pose.legs[0].hip.y - 3.6;
          const hipX = (pose.legs[0].hip.x + pose.legs[1].hip.x) / 2;
          const topHalf = pose.torsoHalf + 0.3;
          const botHalf = topHalf + 3.4 - Math.abs(pose.sin) * 0.8;
          const h = 9.4;
          g.anchor(hipX, hipY);
          g.fill(hipX - botHalf - 2, hipY, hipX + botHalf + 2, hipY + h + 1.4, (x, y) => {
            const p = (y - hipY) / h;
            if (p < 0 || p > 1.05) return -1;
            const cx = hipX + sway * p;
            const hw = topHalf + (botHalf - topHalf) * p;
            const nx = (x - cx) / hw;
            if (Math.abs(nx) > 1) return -1;
            const pleat = Math.sin(nx * 14 + pose.sin * 2.2);
            const hemY = hipY + h + 0.55 * pleat;
            if (y > hemY) return -1;
            const distBottom = hemY - y;
            if (distBottom > 0.9 && distBottom < 2.1) {
              ctx.pal("trim");
              return g.t(nx * z + Math.sqrt(Math.max(0, 1 - nx * nx)) * Q, 0.25);
            }
            ctx.pal("main");
            return g.t(nx * z + Math.sqrt(Math.max(0, 1 - nx * nx)) * Q + pleat * 0.38, -0.05);
          });
        }
      }
    ]
  };
  Me(pleatedSkirt, "expansion/bottom/pleated_skirt");

  // Brand-new procedural bottom: Shorts + Knee Socks
  const shortsBrown = k("shorts-brown", "#1c1008", "#4c301a", "#7e5432", "#b08252", "#deb682");
  const shortsSocks = {
    id: "bottom_shorts_socks",
    name: "短裤配长袜",
    slot: "bottom",
    palettes: { main: shortsBrown, sock: sockWhite },
    variants: [
      { id: "brown", name: "暖棕", palettes: { main: shortsBrown } },
      { id: "white", name: "雪白", palettes: { main: sockWhite } },
      { id: "navy",  name: "藏蓝", palettes: { main: skirtNavy } },
      { id: "khaki", name: "卡其", palettes: { main: k("shorts-khaki", "#241a0e", "#5a462c", "#90744e", "#bea278", "#e6d2ae") } }
    ],
    parts: [
      drawSockLeg(0),
      drawSockLeg(1),
      ...[0, 1].map(idx => ({
        layer: "bottom",
        draw: ctx => {
          const { g } = ctx;
          const leg = ctx.pose.legs[idx];
          const shade = ut(ctx, leg.foot);
          ctx.pal("main");
          g.anchor(leg.knee.x, leg.knee.y);
          g.capsule(leg.hip.x, leg.hip.y, leg.knee.x, leg.knee.y - 1.2, 2.7, 2.5, c => g.t(c, shade + 0.05));
        }
      })),
      {
        layer: "bottom",
        draw: ctx => {
          const { g, pose } = ctx;
          const a = pose.torsoHalf - 0.1;
          const n = pose.legs[0].hip.y;
          const r = (pose.legs[0].hip.x + pose.legs[1].hip.x) / 2;
          ctx.pal("main");
          g.fill(r - a, n - 4.5, r + a, n + 2.5, (x, y) => {
            const l = (x - r) / a;
            return Math.abs(l) > 1 || y < n - 4.5 || y > n + 1.2 ? -1 : g.t(l * z + Math.sqrt(1 - l * l) * Q, -0.1);
          });
        }
      }
    ]
  };
  Me(shortsSocks, "expansion/bottom/shorts_socks");

  // Brand-new procedural bottom: Wide Hakama / Traditional Robe Skirt-Pants
  const hakamaCrimson = k("hakama-crimson", "#24060c", "#5c1220", "#982436", "#cc4e5c", "#f69298");
  const hakama = {
    id: "bottom_hakama",
    name: "阔腿长袴",
    slot: "bottom",
    palettes: { main: hakamaCrimson },
    variants: [
      { id: "crimson", name: "绯红", palettes: { main: hakamaCrimson } },
      { id: "ivory",   name: "月白", palettes: { main: k("hakama-ivory", "#343642", "#787c8c", "#babec8", "#e6e8ec", "#ffffff") } },
      { id: "navy",    name: "靛青", palettes: { main: skirtNavy } },
      { id: "teal",    name: "青玉", palettes: { main: k("hakama-teal", "#0a2022", "#184e50", "#2a8480", "#58bab0", "#a6e8dc") } }
    ],
    parts: [
      ...[0, 1].map(idx => ({
        layer: "bottom",
        draw: ctx => {
          const { g } = ctx;
          const leg = ctx.pose.legs[idx];
          const shade = ut(ctx, leg.foot);
          ctx.pal("main");
          g.anchor(leg.foot.x, leg.foot.y - 4);
          g.capsule(leg.hip.x, leg.hip.y, leg.knee.x, leg.knee.y, 3.1, 3.0, c => g.t(c, shade + 0.05));
          g.capsule(leg.knee.x, leg.knee.y, leg.foot.x, leg.foot.y - 3.6, 3.0, 2.8, c => g.t(c, shade + 0.05));
        }
      })),
      {
        layer: "bottom",
        draw: ctx => {
          const { g, pose } = ctx;
          const a = pose.torsoHalf + 0.8;
          const n = pose.legs[0].hip.y;
          const r = (pose.legs[0].hip.x + pose.legs[1].hip.x) / 2;
          ctx.pal("main");
          g.fill(r - a, n - 4.5, r + a, n + 4.2, (x, y) => {
            const l = (x - r) / a;
            if (Math.abs(l) > 1 || y < n - 4.5 || y > n + 3.6) return -1;
            const fold = Math.sin(l * 9) * 0.25;
            return g.t(l * z + Math.sqrt(1 - l * l) * Q + fold, -0.05);
          });
        }
      }
    ]
  };
  Me(hakama, "expansion/bottom/hakama");

  // =========================================================================
  // 5. SHARED COSTUME TAILORING HELPERS (native HD-2D shading & animation)
  // =========================================================================

  // Flowing back cape / swallowtail coat-tail / phantom cloak
  function makeBackCape(opts) {
    const {
      mainKey = "main",
      trimKey = "trim",
      liningKey = null,
      lenOffset = 7,
      extraWidth = 3.2,
      splitTail = false,
      asymmetric = false
    } = opts;
    return {
      layer: "cape",
      draw: ctx => {
        const { g, pose } = ctx;
        const { sin, cos } = pose;
        const showingBack = cos < 0.3;
        const walking = pose.anim === "walk";
        const sway = walking ? Math.sin(pose.phase + 1) : 0;
        const topW = (asymmetric ? 4.8 : 6.2) * Math.abs(cos) + 2.8 * Math.abs(sin) + 1.0;
        const botW = topW + extraWidth;
        const cxBase = pose.torsoX(3) - sin * 3.4 + (asymmetric ? -cos * 2.2 : 0);
        const y0 = pose.neckY - 0.3;
        const y1 = Et - lenOffset;
        const folds = 2.0 + Math.abs(cos) * 1.2;
        g.grit = 0.2;
        g.fill(cxBase - botW - 5, y0, cxBase + botW + 5, y1 + 2, (x, y) => {
          const p = Math.min(1, (y - y0) / (y1 - y0));
          if (p < 0) return -1;
          const cx = cxBase + sway * p * 1.5 - sin * p * 2.1;
          const hw = topW + (botW - topW) * p;
          const nx = (x - cx) / hw;
          if (Math.abs(nx) > 1) return -1;
          if (splitTail && p > 0.52 && Math.abs(nx) < (p - 0.52) * 0.42) return -1;
          const wave = nx * folds * Math.PI + p * sway * 0.7;
          const hem = y1 + 0.75 * Math.sin(wave + 0.5) + (walking ? 0.45 * Math.sin(pose.phase * 2 + nx * 2) : 0);
          if (y > hem) return -1;
          const amp = Math.min(1, p * 1.6);
          const ridge = Math.sin(wave + 0.8) * amp;
          if (!showingBack) {
            if (liningKey) {
              ctx.pal(liningKey);
              return g.t(0.1 + ridge * 0.5, -0.2);
            }
            ctx.pal(mainKey);
            return ridge > 0.3 ? 1 : 0;
          }
          let shade = 0.18 + nx * z * 0.85 + ridge * 0.7;
          if (p < 0.12) shade -= 0.55;
          const fromHem = hem - y;
          if (trimKey && fromHem > 1.1 && fromHem < 2.6) {
            ctx.pal(trimKey);
            return g.t(shade, 0.25);
          }
          ctx.pal(mainKey);
          return g.t(shade);
        });
      }
    };
  }

  // Crisp pixel ribbon bow (for sailor tie, sundress apron bow, kimono obi bow, idol waist bow)
  function drawBow(ctx, cx, cy, scale, key) {
    const { g } = ctx;
    ctx.pal(key);
    g.ellipse(cx - 1.7 * scale, cy, 1.45 * scale, 1.1 * scale, s => g.t(s, 0.15));
    g.ellipse(cx + 1.7 * scale, cy, 1.45 * scale, 1.1 * scale, s => g.t(s, 0.0));
    g.ellipse(cx, cy, 0.9 * scale, 0.9 * scale, s => s > 0.1 ? 4 : 2);
    g.capsule(cx - 0.5 * scale, cy + 0.6 * scale, cx - 1.6 * scale, cy + 3.0 * scale, 0.7 * scale, 0.55 * scale, s => g.t(s, 0.05));
    g.capsule(cx + 0.5 * scale, cy + 0.6 * scale, cx + 1.6 * scale, cy + 3.0 * scale, 0.7 * scale, 0.55 * scale, s => g.t(s, -0.1));
  }

  // Long dress / robe / coat skirt extension attached smoothly to torso waist
  function drawExtendedSkirt(ctx, startP, totalH, flare, drawFn) {
    const { g, pose } = ctx;
    const sway = pose.anim === "walk" ? Math.sin(pose.phase) * 0.9 : 0;
    const ny = pose.neckY;
    const baseHalf = pose.torsoHalf;
    const padX = Math.abs(pose.torsoX(0) - pose.torsoX(totalH)) + flare + 3;
    g.fill(pt - baseHalf - padX, ny + startP - 1, pt + baseHalf + padX, ny + totalH + 1.5, (x, y) => {
      const p = y - ny;
      if (p < startP || p > totalH) return -1;
      const t = (p - startP) / Math.max(0.1, totalH - startP);
      const cx = pose.torsoX(Math.min(13.2, p)) + sway * t * t;
      const hw = baseHalf + flare * Math.pow(t, 0.95);
      const nx = (x - cx) / hw;
      if (Math.abs(nx) > 1) return -1;
      const shade = nx * z + Math.sqrt(Math.max(0, 1 - nx * nx)) * Q + 0.05;
      return drawFn(shade, nx, p, t, x, y);
    });
  }

  // Short puffy sleeves helper
  function makePuffSleeves(key, cuffKey, length = 0.45, radius = 2.4) {
    const sideFn = side => ({
      layer: ue(side),
      draw: ctx => {
        const { g } = ctx;
        const arm = wt(ctx, side);
        const sh = ut(ctx, arm.hand);
        ctx.pal(key);
        g.anchor(arm.shoulder.x, arm.shoulder.y);
        g.ellipse(arm.shoulder.x, arm.shoulder.y + 0.9, radius + 0.5, radius + 0.3, s => g.t(s, sh + 0.1));
        const end = Pe(ctx, side, [radius, radius + 0.1, radius - 0.3], length);
        if (cuffKey) {
          ctx.pal(cuffKey);
          g.ellipse(end.x, end.y, radius - 0.1, 1.0, s => g.t(s, sh + 0.2));
        }
      }
    });
    return [sideFn("L"), sideFn("R")];
  }

  // =========================================================================
  // 6. 16 BRAND-NEW ORIGINAL NON-EQUIPMENT COSTUMES (时装)
  // =========================================================================
  const GOLD_TRIM = k("cst-gold", "#3e2408", "#8a5c16", "#d8a430", "#f6d86c", "#fff6c0");
  const IVORY_WHITE = k("cst-ivory", "#3a3e52", "#82889e", "#c4c6ce", "#eeece4", "#fffdf6");
  const CRIMSON_ACC = k("cst-crimson", "#2c060c", "#6e121e", "#b82434", "#e85458", "#ffa4a0");
  const LEATHER_BELT = k("cst-leather", "#160a06", "#3a2210", "#643e22", "#946438", "#c4945e");

  // --- 1. 学院制服 (Academy Blazer Uniform) ---
  const academyNavy = k("cst-acad-navy", "#0a1026", "#1a2854", "#2c4484", "#4a6ab0", "#86a8e4");
  Me({
    id: "top_costume_academy",
    name: "学院制服",
    slot: "top",
    palettes: { main: academyNavy, shirt: IVORY_WHITE, tie: CRIMSON_ACC, gold: GOLD_TRIM },
    variants: [
      { id: "navy",   name: "学院蓝", palettes: { main: academyNavy, tie: CRIMSON_ACC } },
      { id: "forest", name: "常春藤绿", palettes: { main: k("cst-acad-green", "#081c14", "#164430", "#267050", "#46a074", "#86d4a8"), tie: GOLD_TRIM } },
      { id: "wine",   name: "英伦酒红", palettes: { main: k("cst-acad-wine", "#240812", "#581628", "#8e2842", "#c0526c", "#f094a8"), tie: academyNavy } }
    ],
    parts: [
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx;
          const ny = pose.neckY, hw = pose.torsoHalf;
          ctx.pal("main");
          J(ctx, 13.8, { flare: 1.8 }, (s, nx, p) => {
            if (p < 2.2) return 0;
            if (p > 12.6) { ctx.pal("gold"); return g.t(s, 0.15); }
            ctx.pal("main");
            return g.t(s, p > 9.5 ? -0.06 : 0.04);
          });
          g.clip = true;
          if (pose.cos > 0.3) {
            const cx = gt(ctx);
            // Crisp white V-shirt & collar
            ctx.pal("shirt");
            g.tri({ x: cx - 3.6, y: ny + 1.8 }, { x: cx + 3.6, y: ny + 1.8 }, { x: cx, y: ny + 7.6 }, 4);
            // Crimson necktie
            ctx.pal("tie");
            g.line(cx, ny + 3.2, cx, ny + 8.6, 3);
            g.ellipse(cx, ny + 3.2, 1.1, 0.9, s => s > 0 ? 4 : 2);
            // Gold blazer buttons & tiny academy crest
            ctx.pal("gold");
            g.dot(cx - 2.6, ny + 5.6, 4);
            g.dot(cx - 2.6, ny + 6.4, 3);
            g.dot(cx + 1.3, ny + 9.2, 4);
            g.dot(cx + 1.3, ny + 11.2, 4);
            ctx.pal("main");
            g.line(cx, ny + 8.2, cx, ny + 13.2, V);
          } else if (pose.cos < -0.3) {
            const cx = pose.torsoX(6) - hw * 0.3 * pose.sin;
            g.line(cx, ny + 8.8, cx, ny + 13.2, V);
            ctx.pal("gold");
            g.line(cx - 2.6, ny + 8.4, cx + 2.6, ny + 8.4, 3);
          }
          g.clip = false;
        }
      },
      ...Mt({ key: "main", cuffKey: "gold", r: 2.0 })
    ]
  }, "expansion/top/costume_academy");

  // --- 2. 海风海军装 (Sailor Uniform) ---
  const sailorBlue = k("cst-sailor-blue", "#08122c", "#162c64", "#2850a0", "#4e80d4", "#98c2f8");
  Me({
    id: "top_costume_sailor",
    name: "海风海军装",
    slot: "top",
    palettes: { main: IVORY_WHITE, collar: sailorBlue, tie: CRIMSON_ACC },
    variants: [
      { id: "navy",   name: "经典海蓝", palettes: { collar: sailorBlue, tie: CRIMSON_ACC } },
      { id: "sky",    name: "晴空天蓝", palettes: { collar: k("cst-sailor-sky", "#102a4a", "#26649e", "#4ca4e0", "#8cd6fa", "#daf6ff"), tie: GOLD_TRIM } }
    ],
    parts: [
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx;
          const ny = pose.neckY;
          ctx.pal("main");
          J(ctx, 13.0, { flare: 1.5 }, (s, nx, p) => {
            if (p < 2.2) return 0;
            if (p > 11.4) { ctx.pal("collar"); return g.t(s, -0.05); }
            ctx.pal("main");
            return g.t(s, 0.08);
          });
          g.clip = true;
          g.fold(pose.torsoX(6) - pose.torsoHalf + 1.2, ny + 6.5, pose.torsoX(6) - pose.torsoHalf + 3.6, ny + 8.6);
          g.fold(pose.torsoX(6) + pose.torsoHalf - 1.2, ny + 6.2, pose.torsoX(6) + pose.torsoHalf - 3.4, ny + 8.4);
          g.clip = false;
        }
      },
      ...Mt({ key: "main", cuffKey: "collar", r: 2.0 }),
      // Iconic sailor collar: V-cut front + square double-striped sailor flap on back!
      {
        layer: "mantle",
        draw: ctx => {
          const { g, pose } = ctx;
          const ny = pose.neckY;
          const hw = pose.torsoHalf + 2.4;
          const cx = pose.torsoX(1);
          if (pose.cos < -0.25) {
            // Back square sailor flap with bright white border stripe
            const flapW = hw * 0.92;
            const y0 = ny - 0.8, y1 = ny + 7.2;
            g.fill(cx - flapW, y0, cx + flapW, y1, (x, y) => {
              const nx = (x - cx) / flapW;
              if (Math.abs(nx) > 1 || y < y0 || y > y1) return -1;
              const edgeX = flapW - Math.abs(x - cx);
              const edgeY = y1 - y;
              const isStripe = (edgeY > 0.9 && edgeY < 2.0) || (edgeX > 0.9 && edgeX < 2.0 && y > y0 + 1.2);
              ctx.pal(isStripe ? "main" : "collar");
              return g.t(nx * z + Math.sqrt(Math.max(0, 1 - nx * nx)) * Q, isStripe ? 0.3 : 0.05);
            });
          } else {
            // Front/side draped V sailor collar
            const y0 = ny - 1.0, y1 = ny + 5.6;
            const frontX = gt(ctx);
            g.fill(cx - hw, y0, cx + hw, y1, (x, y) => {
              const nx = (x - cx) / hw;
              if (Math.abs(nx) > 1) return -1;
              const topY = y0 + 1.8 * (1 - Math.sqrt(1 - nx * nx));
              const dFront = Math.abs(x - frontX) / Math.max(2.5, hw);
              const botY = y1 - dFront * 1.4;
              if (y < topY || y > botY) return -1;
              // Open V neckline in center front
              if (pose.cos > 0.2 && Math.abs(x - frontX) < (y - topY) * 0.42 && y < ny + 4.0) return -1;
              const isStripe = botY - y > 0.7 && botY - y < 1.8;
              ctx.pal(isStripe ? "main" : "collar");
              return g.t(nx * z + Math.sqrt(Math.max(0, 1 - nx * nx)) * Q, isStripe ? 0.3 : 0.05);
            });
            if (pose.cos > 0.25) {
              drawBow(ctx, frontX, ny + 4.8, 0.95, "tie");
            }
          }
        }
      }
    ]
  }, "expansion/top/costume_sailor");

  // --- 3. 星夜学院袍 (Starry Academy Mage Robe — scholarly robe, NOT armor!) ---
  const mageIndigo = k("cst-mage-indigo", "#0c0e2c", "#1e2262", "#343c96", "#5862c8", "#9ca8f2");
  const mageViolet = k("cst-mage-violet", "#1e0c36", "#4e227c", "#8442ba", "#ba7ae8", "#ebd0ff");
  Me({
    id: "top_costume_mage_robe",
    name: "星夜学院袍",
    slot: "top",
    palettes: { main: mageIndigo, sash: mageViolet, trim: GOLD_TRIM },
    variants: [
      { id: "indigo",  name: "星夜靛", palettes: { main: mageIndigo, sash: mageViolet } },
      { id: "emerald", name: "秘境绿", palettes: { main: k("cst-mage-grn", "#081c18", "#14483a", "#247c60", "#48b48a", "#92e8c0"), sash: GOLD_TRIM } },
      { id: "crimson", name: "赤焰红", palettes: { main: CRIMSON_ACC, sash: GOLD_TRIM } }
    ],
    parts: [
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx;
          const ny = pose.neckY;
          // Flowing long wizard robe extending down over thighs with gold hem & vertical celestial stole
          drawExtendedSkirt(ctx, 0, 19.6, 4.4, (s, nx, p, t) => {
            if (p < 2.2) { ctx.pal("main"); return 0; }
            const distBot = 19.6 - p;
            if (distBot < 2.1 && distBot > 0.6) {
              ctx.pal("trim");
              return g.t(s, 0.25);
            }
            if (p > 8.2 && p < 10.4) {
              ctx.pal("sash");
              return g.t(s, 0.12);
            }
            // Central vertical gold stole band on front
            if (pose.cos > 0.3 && Math.abs(nx - pose.sin * 0.55) < 0.18 && p > 2.8 && p < 18.6) {
              ctx.pal("trim");
              return g.t(s, 0.22);
            }
            ctx.pal("main");
            const pleat = p > 10 ? Math.sin(nx * 10) * 0.22 : 0;
            return g.t(s + pleat, p < 3.4 ? -0.2 : 0.04);
          });
          // Tiny golden stars along the front hem/chest
          if (pose.cos > 0.3) {
            const cx = gt(ctx);
            ctx.pal("trim");
            g.clip = true;
            g.dot(cx, ny + 5.2, 4);
            g.dot(cx - 3.6, ny + 15.8, 4);
            g.dot(cx + 3.6, ny + 15.8, 4);
            g.clip = false;
          }
        }
      },
      ...Mt({ key: "main", cuffKey: "trim", r: 2.35, length: 0.78 }),
      // Scholarly shoulder capelet with gold crescent clasp
      {
        layer: "mantle",
        draw: ctx => {
          const { g, pose } = ctx;
          const ny = pose.neckY;
          const hw = pose.torsoHalf + 2.6;
          const cx = pose.torsoX(1);
          const y0 = ny - 1.6, y1 = ny + 4.4;
          g.fill(cx - hw, y0, cx + hw, y1 + 1.2, (x, y) => {
            const nx = (x - cx) / hw;
            if (Math.abs(nx) > 1) return -1;
            const top = y0 + 2.2 * (1 - Math.sqrt(1 - nx * nx));
            const bot = y1 + 0.7 * Math.cos(nx * 5);
            if (y < top || y > bot) return -1;
            const isTrim = bot - y > 0.5 && bot - y < 1.6;
            ctx.pal(isTrim ? "trim" : "sash");
            return g.t(nx * z + Math.sqrt(Math.max(0, 1 - nx * nx)) * Q, isTrim ? 0.25 : 0.05);
          });
          if (pose.cos > 0.3) {
            const fx = gt(ctx);
            ctx.pal("trim");
            g.ellipse(fx, ny + 1.6, 1.35, 1.35, s => s > 0.3 ? 4 : 3);
          }
        }
      }
    ]
  }, "expansion/top/costume_mage_robe");

  // --- 4. 元气连帽卫衣 (Cozy Pullover Hoodie) ---
  const hoodieCoral = k("cst-hoodie-coral", "#3c120a", "#8c321c", "#dc623a", "#f89a66", "#ffdcb8");
  const hoodieMint = k("cst-hoodie-mint", "#12342c", "#2c7462", "#58b498", "#9ae0c4", "#dffef0");
  Me({
    id: "top_costume_hoodie",
    name: "元气连帽卫衣",
    slot: "top",
    palettes: { main: hoodieCoral, trim: IVORY_WHITE },
    variants: [
      { id: "coral", name: "元气珊瑚", palettes: { main: hoodieCoral } },
      { id: "mint",  name: "清新薄荷", palettes: { main: hoodieMint } },
      { id: "sky",   name: "天空蓝",   palettes: { main: k("cst-hoodie-sky", "#102644", "#245c94", "#4898d8", "#88ccf8", "#daf4ff") } }
    ],
    parts: [
      // Hood resting behind neck (clearly readable from SE, E, NE, N!)
      {
        layer: "cape",
        draw: ctx => {
          const { g, pose } = ctx;
          if (pose.cos > 0.65) return;
          const cx = pose.torsoX(1) - pose.sin * 2.8;
          const cy = pose.neckY + 1.8;
          const rx = 5.4 - Math.abs(pose.sin) * 1.1;
          const ry = 4.2;
          ctx.pal("main");
          g.ellipse(cx, cy, rx, ry, (s, lx, ly) => g.t(s, ly > 0.3 ? -0.25 : 0.1));
          g.clip = true;
          g.line(cx - rx * 0.6, cy + 1.0, cx + rx * 0.6, cy + 1.0, V);
          g.clip = false;
        }
      },
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx;
          const ny = pose.neckY, hw = pose.torsoHalf;
          ctx.pal("main");
          J(ctx, 13.6, { flare: 1.4, pad: 0.4 }, (s, nx, p) => {
            if (p < 2.2) return 0;
            if (p > 11.4) { ctx.pal("trim"); return g.t(s, 0.12); }
            ctx.pal("main");
            return g.t(s, p > 7.8 && p < 11.2 ? 0.08 : 0.0);
          });
          g.clip = true;
          if (pose.cos > 0.3) {
            const cx = gt(ctx);
            // Kangaroo pocket outline & cream drawstrings
            g.line(cx - 3.4, ny + 8.0, cx + 3.4, ny + 8.0, V);
            g.line(cx - 3.6, ny + 8.2, cx - 4.4, ny + 11.0, V);
            g.line(cx + 3.6, ny + 8.2, cx + 4.4, ny + 11.0, V);
            ctx.pal("trim");
            g.line(cx - 1.3, ny + 3.0, cx - 1.5, ny + 6.8, 4);
            g.line(cx + 1.3, ny + 3.0, cx + 1.5, ny + 6.8, 4);
          } else {
            g.fold(pose.torsoX(6) - hw + 1.2, ny + 5.5, pose.torsoX(6) + hw - 1.2, ny + 6.8);
          }
          g.clip = false;
        }
      },
      ...Mt({ key: "main", cuffKey: "trim", r: 2.25 }),
      // Thick rolled hoodie collar encircling neck
      {
        layer: "mantle",
        draw: ctx => {
          const { g, pose } = ctx;
          const cx = pose.torsoX(0) - pose.sin * 0.5;
          const cy = pose.neckY + 0.8;
          const rx = pose.torsoHalf + 1.2;
          ctx.pal("main");
          g.ellipse(cx, cy, rx, 2.3, (s, lx, ly) => g.t(s, ly < -0.2 ? 0.2 : -0.1));
        }
      }
    ]
  }, "expansion/top/costume_hoodie");

  // --- 5. 森林背带装 (Adventurer Denim Overalls over Puffy Shirt) ---
  const denimBib = k("cst-denim-bib", "#0e1a2e", "#22406a", "#3c6ba0", "#689cd0", "#a6cef2");
  const shirtCream = k("cst-shirt-cream", "#403628", "#887860", "#c8bc9e", "#ece4cc", "#fffcf0");
  Me({
    id: "top_costume_overalls",
    name: "森林背带装",
    slot: "top",
    palettes: { main: denimBib, shirt: shirtCream, gold: GOLD_TRIM },
    variants: [
      { id: "denim",      name: "复古丹宁", palettes: { main: denimBib } },
      { id: "terracotta", name: "暖焦糖",   palettes: { main: k("cst-ov-terra", "#2e120a", "#6e321a", "#b05a32", "#dc8c5a", "#f8c89a") } },
      { id: "moss",       name: "林间苔绿", palettes: { main: k("cst-ov-moss",  "#102012", "#28502c", "#468046", "#74b26a", "#b4e0a4") } }
    ],
    parts: [
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx;
          const ny = pose.neckY;
          // Cream shirt base + denim bib & straps
          J(ctx, 13.4, { flare: 1.4 }, (s, nx, p) => {
            if (p < 2.0) { ctx.pal("shirt"); return 0; }
            if (p > 9.4) { ctx.pal("main"); return g.t(s, -0.05); }
            // Front bib panel + twin suspender straps
            if (pose.cos > 0.2) {
              const cx = nx - pose.sin * 0.55;
              const inBib = p > 4.4 && Math.abs(cx) < 0.62;
              const inStrap = p <= 4.6 && (Math.abs(cx + 0.42) < 0.16 || Math.abs(cx - 0.42) < 0.16);
              if (inBib || inStrap) { ctx.pal("main"); return g.t(s, 0.08); }
            } else if (pose.cos < -0.2) {
              // Back X-straps!
              const t = (p - 2.0) / 7.4;
              const s1 = -0.45 + 0.9 * t, s2 = 0.45 - 0.9 * t;
              if (Math.abs(nx - s1) < 0.16 || Math.abs(nx - s2) < 0.16) { ctx.pal("main"); return g.t(s, 0.05); }
            } else {
              // Side view strap
              if (Math.abs(nx) < 0.24) { ctx.pal("main"); return g.t(s, 0.05); }
            }
            ctx.pal("shirt");
            return g.t(s, 0.12);
          });
          // Brass bib buttons + front pocket stitching
          if (pose.cos > 0.3) {
            const cx = gt(ctx);
            g.clip = true;
            ctx.pal("gold");
            g.dot(cx - 2.6, ny + 5.0, 4);
            g.dot(cx + 2.6, ny + 5.0, 4);
            ctx.pal("main");
            g.line(cx - 2.0, ny + 7.2, cx + 2.0, ny + 7.2, V);
            g.clip = false;
          }
        }
      },
      ...makePuffSleeves("shirt", "main", 0.56, 2.2)
    ]
  }, "expansion/top/costume_overalls");

  // --- 6. 樱韵和服 (Sakura Kimono + Taiko Obi) ---
  const kimonoSakura = k("cst-kim-sakura", "#421628", "#8e3c5c", "#d87498", "#f6b0ca", "#ffe8f2");
  const kimonoObi = k("cst-kim-obi", "#0a102a", "#1c2860", "#304894", "#5674c4", "#98b8f2");
  Me({
    id: "top_costume_kimono",
    name: "樱韵和服",
    slot: "top",
    palettes: { main: kimonoSakura, collar: IVORY_WHITE, obi: kimonoObi, gold: GOLD_TRIM },
    variants: [
      { id: "sakura", name: "樱粉", palettes: { main: kimonoSakura, obi: kimonoObi } },
      { id: "indigo", name: "靛蓝", palettes: { main: kimonoObi, obi: CRIMSON_ACC } },
      { id: "jade",   name: "青瓷", palettes: { main: k("cst-kim-jade", "#0e2a28", "#20645e", "#3ea496", "#84dac8", "#d2f8ee"), obi: CRIMSON_ACC } }
    ],
    parts: [
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx;
          const ny = pose.neckY;
          drawExtendedSkirt(ctx, 0, 19.2, 2.6, (s, nx, p) => {
            if (p < 2.0) { ctx.pal("collar"); return 2; }
            // Wide brocade obi sash around waist
            if (p >= 7.6 && p <= 11.4) {
              if (p > 9.1 && p < 10.0) { ctx.pal("gold"); return g.t(s, 0.35); }
              ctx.pal("obi");
              return g.t(s, 0.05);
            }
            // Diagonal white crossover kimono collar (Y-lapel) on front
            if (pose.cos > 0.25 && p < 7.8) {
              const fx = nx - pose.sin * 0.55;
              const leftDiag = Math.abs(fx - (-0.42 + (p - 2.0) * 0.11));
              const rightDiag = Math.abs(fx - (0.42 - (p - 2.0) * 0.11));
              if (leftDiag < 0.16 || (rightDiag < 0.16 && p < 5.6)) {
                ctx.pal("collar");
                return g.t(s, 0.25);
              }
            }
            // Subtle kimono hem border
            if (p > 17.4) {
              ctx.pal("obi");
              return g.t(s, 0.05);
            }
            ctx.pal("main");
            // Subtle sakura petal specks on skirt
            const petal = p > 12.2 && ((Math.floor(nx * 6 + 10) + Math.floor(p * 0.7)) % 5 === 0);
            return g.t(s, petal ? 0.55 : 0.04);
          });
          // Iconic square taiko obi bow on the back!
          if (pose.cos < -0.25) {
            const bx = pose.torsoX(8) - pose.sin * 1.4;
            ctx.pal("obi");
            g.rect(bx - 3.6, ny + 6.4, 7.2, 5.4, (x, y) => {
              const rx = (x - bx) / 3.6;
              return g.t(rx * z + 0.35, y > ny + 10.4 ? -0.3 : 0.12);
            });
            ctx.pal("gold");
            g.line(bx - 3.4, ny + 9.2, bx + 3.4, ny + 9.2, 4);
          }
        }
      },
      // Flowing wide kimono sleeves
      ...Mt({ key: "main", cuffKey: "collar", r: 2.55, length: 0.76 })
    ]
  }, "expansion/top/costume_kimono");

  // --- 7. 青玉侠客衫 (Jade-White Traditional Hanfu Adventurer Robe) ---
  const hanfuJade = k("cst-hf-jade", "#0c2624", "#1c5e58", "#329c90", "#70d4c2", "#c4f6ea");
  const hanfuWhite = k("cst-hf-white", "#323a46", "#7a8696", "#bec6d0", "#eaedf0", "#ffffff");
  Me({
    id: "top_costume_hanfu",
    name: "青玉侠客衫",
    slot: "top",
    palettes: { main: hanfuWhite, trim: hanfuJade, gold: GOLD_TRIM },
    variants: [
      { id: "jade",  name: "青玉白", palettes: { main: hanfuWhite, trim: hanfuJade } },
      { id: "ink",   name: "水墨玄", palettes: { main: k("cst-hf-ink", "#0a0c14", "#1e2436", "#38425c", "#647292", "#a2b0ce"), trim: GOLD_TRIM } },
      { id: "cloud", name: "云霞绯", palettes: { main: hanfuWhite, trim: CRIMSON_ACC } }
    ],
    parts: [
      makeBackCape({ mainKey: "trim", trimKey: "gold", lenOffset: 10, extraWidth: 1.8, splitTail: true }),
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx;
          const ny = pose.neckY;
          drawExtendedSkirt(ctx, 0, 19.0, 3.2, (s, nx, p) => {
            if (p < 2.0) { ctx.pal("trim"); return 1; }
            // Split front lower panels showing movement
            if (p > 13.8 && pose.cos > 0.2 && Math.abs(nx - pose.sin * 0.5) < (p - 13.8) * 0.045) return -1;
            // Jade belt sash
            if (p >= 8.2 && p <= 10.6) {
              ctx.pal("trim");
              return g.t(s, p > 9.9 ? -0.25 : 0.15);
            }
            // Crossed right-over-left Hanfu collar (交领右衽)
            if (pose.cos > 0.25 && p < 8.2) {
              const fx = nx - pose.sin * 0.55;
              const lapel = Math.abs(fx - (-0.42 + (p - 2.0) * 0.14));
              if (lapel < 0.16) { ctx.pal("trim"); return g.t(s, 0.2); }
            }
            // Flowing vertical jade border trim
            if (p > 17.2) { ctx.pal("trim"); return g.t(s, 0.15); }
            ctx.pal("main");
            return g.t(s, 0.08);
          });
          // Hanging jade & gold waist pendant tassel
          if (pose.cos > 0.25) {
            const cx = gt(ctx);
            ctx.pal("gold");
            g.ellipse(cx + 1.6, ny + 9.4, 1.1, 1.1, s => s > 0 ? 4 : 3);
            ctx.pal("trim");
            g.line(cx + 1.6, ny + 10.6, cx + 1.8, ny + 15.2, 3);
            g.dot(cx + 1.8, ny + 15.5, 4);
          }
        }
      },
      ...Mt({ key: "main", cuffKey: "trim", r: 2.3, length: 0.78 })
    ]
  }, "expansion/top/costume_hanfu");

  // --- 8. 宫廷小礼服 (Aristocratic Wine & Ivory Tailcoat) ---
  const nobleWine = k("cst-nob-wine", "#26060e", "#5e1222", "#9a2238", "#ce5062", "#f894a0");
  Me({
    id: "top_costume_noble",
    name: "宫廷小礼服",
    slot: "top",
    palettes: { main: nobleWine, lace: IVORY_WHITE, gold: GOLD_TRIM },
    variants: [
      { id: "wine",  name: "酒红宫廷", palettes: { main: nobleWine } },
      { id: "royal", name: "皇家蓝",   palettes: { main: academyNavy } }
    ],
    layerOverride: d => (d === "N" || d === "NE" ? { cape: Le.mantle - 1 } : {}),
    parts: [
      // Split swallowtail coat-tails at the back!
      makeBackCape({ mainKey: "main", trimKey: "gold", lenOffset: 9, extraWidth: 1.6, splitTail: true }),
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx;
          const ny = pose.neckY;
          ctx.pal("main");
          J(ctx, 13.4, { flare: 1.6 }, (s, nx, p) => {
            if (p < 2.2) return 0;
            if (p > 11.8) { ctx.pal("gold"); return g.t(s, 0.2); }
            ctx.pal("main");
            return g.t(s, 0.05);
          });
          g.clip = true;
          if (pose.cos > 0.3) {
            const cx = gt(ctx);
            // Ruffled ivory jabot cravat
            ctx.pal("lace");
            g.ellipse(cx, ny + 4.4, 2.0, 2.6, s => g.t(s, 0.25));
            // Gold double-breasted frogging stripes
            ctx.pal("gold");
            for (const row of [5.8, 7.8, 9.8]) {
              g.line(cx - 3.2, ny + row, cx - 1.2, ny + row, 4);
              g.line(cx + 1.2, ny + row, cx + 3.2, ny + row, 3);
            }
          }
          g.clip = false;
        }
      },
      ...Mt({ key: "main", cuffKey: "lace", r: 2.0 }),
      ...ae({ key: "main", trimKey: "gold", r: 2.4 })
    ]
  }, "expansion/top/costume_noble");

  // --- 9. 向日葵田园裙 (Sunflower Countryside Sundress + White Apron) ---
  const sunGold = k("cst-sun-gold", "#3e2206", "#905a12", "#e0a224", "#fad458", "#fff6b0");
  Me({
    id: "top_costume_sundress",
    name: "向日葵田园裙",
    slot: "top",
    palettes: { main: sunGold, apron: IVORY_WHITE, ribbon: CRIMSON_ACC },
    variants: [
      { id: "sunflower", name: "向日葵黄", palettes: { main: sunGold } },
      { id: "peach",     name: "蜜桃粉",   palettes: { main: kimonoSakura } },
      { id: "sky",       name: "晴空蓝",   palettes: { main: k("cst-sun-sky", "#102846", "#28649e", "#52a8e2", "#96dafc", "#e2f8ff") } }
    ],
    parts: [
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx;
          const ny = pose.neckY;
          drawExtendedSkirt(ctx, 0, 19.4, 5.2, (s, nx, p, t) => {
            if (p < 2.2) { ctx.pal("apron"); return 3; }
            // Crisp white scalloped lace hem along the bottom
            const distBot = 19.4 - p;
            if (distBot < 1.9 + 0.45 * Math.sin(nx * 16)) {
              ctx.pal("apron");
              return g.t(s, 0.25);
            }
            // White waist sash
            if (p >= 7.8 && p <= 9.6) {
              ctx.pal("apron");
              return g.t(s, 0.2);
            }
            // Front pinafore apron panel
            if (pose.cos > 0.25 && p > 9.4 && p < 16.6 && Math.abs(nx - pose.sin * 0.48) < 0.46) {
              ctx.pal("apron");
              return g.t(s, 0.18);
            }
            ctx.pal("main");
            const gather = p > 9.4 ? Math.sin(nx * 13) * 0.28 : 0;
            return g.t(s + gather, 0.08);
          });
          // Sweet bow on back waist, or tiny red ribbon bow at front collar!
          if (pose.cos < -0.25) {
            drawBow(ctx, pose.torsoX(9) - pose.sin * 1.2, ny + 9.2, 1.05, "apron");
          } else if (pose.cos > 0.3) {
            drawBow(ctx, gt(ctx), ny + 3.4, 0.72, "ribbon");
          }
        }
      },
      ...makePuffSleeves("main", "apron", 0.42, 2.35)
    ]
  }, "expansion/top/costume_sundress");

  // --- 10. 航海船长装 (Sea Captain's Long Greatcoat with Gold Epaulettes) ---
  const capCrimson = k("cst-cap-red", "#28060a", "#66121a", "#aa242c", "#dc524c", "#fa9686");
  Me({
    id: "top_costume_captain",
    name: "航海船长装",
    slot: "top",
    palettes: { main: capCrimson, vest: IVORY_WHITE, belt: LEATHER_BELT, gold: GOLD_TRIM },
    variants: [
      { id: "crimson", name: "赤红船长", palettes: { main: capCrimson } },
      { id: "navy",    name: "深海船长", palettes: { main: academyNavy } }
    ],
    parts: [
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx;
          const ny = pose.neckY;
          drawExtendedSkirt(ctx, 0, 18.6, 3.8, (s, nx, p) => {
            if (p < 2.2) { ctx.pal("main"); return 0; }
            // Open coat front revealing cream waistcoat + gold trim lapels
            if (pose.cos > 0.25) {
              const fx = nx - pose.sin * 0.55;
              if (p > 12.6 && Math.abs(fx) < 0.24) return -1; // open lower greatcoat slit
              if (p <= 12.6 && Math.abs(fx) < 0.28) {
                ctx.pal("vest");
                return g.t(s, 0.15);
              }
              if (Math.abs(Math.abs(fx) - 0.32) < 0.10) {
                ctx.pal("gold");
                return g.t(s, 0.25);
              }
            }
            if (p > 17.0) { ctx.pal("gold"); return g.t(s, 0.2); }
            ctx.pal("main");
            return g.t(s, 0.04);
          });
          // Bold leather captain belt with big gold buckle
          uo(ctx, 8.8, 10.8, "belt", "gold");
        }
      },
      ...Mt({ key: "main", cuffKey: "gold", r: 2.15 }),
      // Golden tasseled shoulder epaulettes!
      ...["L", "R"].map(side => ({
        layer: ue(side),
        draw: ctx => {
          const { g } = ctx;
          const arm = wt(ctx, side);
          const sh = ut(ctx, arm.hand);
          const sx = arm.shoulder.x, sy = arm.shoulder.y;
          ctx.pal("gold");
          g.ellipse(sx, sy - 0.2, 3.0, 1.4, s => ct(ctx, s, sh + 0.15));
          // Hanging gold fringe tassels
          for (const dx of [-1.6, -0.5, 0.6, 1.6]) {
            g.line(sx + dx, sy + 0.9, sx + dx, sy + 2.3, dx < 0 ? 4 : 3);
          }
        }
      }))
    ]
  }, "expansion/top/costume_captain");

  // --- 11. 吟游诗人装 (Emerald Minstrel Vest + Jaunty Half-Shoulder Capelet) ---
  const bardEmerald = k("cst-bard-grn", "#0a2214", "#1a5630", "#2e8c4c", "#60c274", "#b0eeaa");
  const bardPlum = k("cst-bard-plum", "#220a24", "#541c56", "#8c348c", "#c064bc", "#f0a8ec");
  Me({
    id: "top_costume_bard",
    name: "吟游诗人装",
    slot: "top",
    palettes: { main: bardEmerald, shirt: shirtCream, cape: bardEmerald, belt: LEATHER_BELT, gold: GOLD_TRIM },
    variants: [
      { id: "emerald", name: "翡翠诗谣", palettes: { main: bardEmerald, cape: bardEmerald } },
      { id: "plum",    name: "紫罗兰诗谣", palettes: { main: bardPlum, cape: bardPlum } }
    ],
    layerOverride: d => (d === "N" || d === "NE" ? { cape: Le.mantle - 1 } : {}),
    parts: [
      makeBackCape({ mainKey: "cape", trimKey: "gold", lenOffset: 14, extraWidth: 2.4, asymmetric: true }),
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx;
          const ny = pose.neckY;
          J(ctx, 13.6, { flare: 2.0 }, (s, nx, p) => {
            if (p < 2.2) { ctx.pal("shirt"); return 2; }
            if (p > 12.2) { ctx.pal("gold"); return g.t(s, 0.2); }
            // Diamond-quilted minstrel vest texture
            ctx.pal("main");
            const diag = ((Math.floor(nx * 5 + p * 0.45 + 10) + Math.floor(nx * 5 - p * 0.45 + 20)) % 2 === 0);
            return g.t(s, diag ? 0.14 : -0.14);
          });
          // Front laced shirt collar opening
          if (pose.cos > 0.3) {
            const cx = gt(ctx);
            g.clip = true;
            ctx.pal("shirt");
            g.tri({ x: cx - 2.4, y: ny + 1.8 }, { x: cx + 2.4, y: ny + 1.8 }, { x: cx, y: ny + 6.0 }, 4);
            ctx.pal("gold");
            g.line(cx - 1.2, ny + 3.8, cx + 1.2, ny + 3.8, 3);
            g.line(cx - 0.8, ny + 5.0, cx + 0.8, ny + 5.0, 3);
            g.clip = false;
          }
          uo(ctx, 9.0, 10.8, "belt", "gold");
        }
      },
      // Puffed white minstrel shirt sleeves with emerald cuffs
      ...Mt({ key: "shirt", cuffKey: "main", r: 2.25 }),
      // Asymmetric half-shoulder minstrel mantle with gold clasp
      {
        layer: "mantle",
        draw: ctx => {
          const { g, pose } = ctx;
          const ny = pose.neckY;
          const cx = pose.torsoX(1) - pose.cos * 2.2;
          const rx = pose.torsoHalf * 0.8 + 1.6;
          ctx.pal("cape");
          g.ellipse(cx, ny + 1.8, rx, 2.8, (s, lx, ly) => {
            if (ly > 0.65) { ctx.pal("gold"); return g.t(s, 0.25); }
            ctx.pal("cape");
            return g.t(s, 0.05);
          });
          if (pose.cos > 0.2) {
            ctx.pal("gold");
            g.ellipse(gt(ctx) - 1.4, ny + 1.6, 1.2, 1.2, s => s > 0.2 ? 4 : 3);
          }
        }
      }
    ]
  }, "expansion/top/costume_bard");

  // --- 12. 冬日毛绒大衣 (Cozy Fur-Trimmed Winter Parka Coat) ---
  const winterSky = k("cst-win-sky", "#102846", "#265c92", "#4c96d2", "#88c8f4", "#d8f2ff");
  const winterBerry = k("cst-win-berry", "#2e0a18", "#701a38", "#b4325c", "#e4688c", "#ffb2c6");
  Me({
    id: "top_costume_winter_coat",
    name: "冬日毛绒大衣",
    slot: "top",
    palettes: { main: winterSky, fur: IVORY_WHITE, toggle: LEATHER_BELT },
    variants: [
      { id: "glacier", name: "冰雪蓝", palettes: { main: winterSky } },
      { id: "berry",   name: "莓果红", palettes: { main: winterBerry } },
      { id: "cocoa",   name: "热可可", palettes: { main: k("cst-win-cocoa", "#24140c", "#583420", "#8e5c3a", "#c28e62", "#ecc89e") } }
    ],
    parts: [
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx;
          const ny = pose.neckY;
          drawExtendedSkirt(ctx, 0, 16.8, 2.8, (s, nx, p) => {
            if (p < 2.2) { ctx.pal("fur"); return 3; }
            // Fluffy thick snow-white fur lower hem band
            const distBot = 16.8 - p;
            if (distBot < 2.5 + 0.35 * Math.sin(nx * 14)) {
              ctx.pal("fur");
              return g.t(s, 0.22);
            }
            ctx.pal("main");
            return g.t(s, 0.04);
          });
          // Wooden duffle toggles down center front
          if (pose.cos > 0.3) {
            const cx = gt(ctx);
            g.clip = true;
            g.line(cx, ny + 3.4, cx, ny + 14.0, V);
            ctx.pal("toggle");
            for (const row of [5.4, 8.2, 11.0]) {
              g.line(cx - 1.8, ny + row, cx + 1.8, ny + row, 3);
              g.dot(cx - 1.8, ny + row, 2);
              g.dot(cx + 1.8, ny + row, 4);
            }
            g.clip = false;
          }
        }
      },
      ...Mt({ key: "main", cuffKey: "fur", r: 2.3 }),
      // Fluffy scalloped snow-white fur collar encircling neck!
      {
        layer: "mantle",
        draw: ctx => {
          const { g, pose } = ctx;
          const ny = pose.neckY;
          const cx = pose.torsoX(0) + pose.sin * 0.4;
          const rx = pose.torsoHalf + 2.0;
          ctx.pal("fur");
          g.fill(cx - rx, ny - 1.8, cx + rx, ny + 3.4, (x, y) => {
            const nx = (x - cx) / rx;
            if (Math.abs(nx) > 1) return -1;
            const puff = 0.55 * Math.sin(nx * 14);
            const ry = 2.4 + puff * 0.45;
            const ny2 = (y - (ny + 0.8)) / ry;
            if (nx * nx + ny2 * ny2 > 1) return -1;
            return g.t(nx * z + ny2 * mt + 0.45, 0.2);
          });
        }
      }
    ]
  }, "expansion/top/costume_winter_coat");

  // --- 13. 探险家工装 (Field Explorer Safari Jacket + Neckerchief) ---
  const expKhaki = k("cst-exp-khaki", "#281e10", "#644e2e", "#a28252", "#d2b47c", "#f6e4b4");
  const expMoss = k("cst-exp-moss", "#0e2212", "#24542a", "#428844", "#76bc6a", "#b8ea9e");
  Me({
    id: "top_costume_explorer",
    name: "探险家工装",
    slot: "top",
    palettes: { main: expKhaki, scarf: expMoss, belt: LEATHER_BELT, gold: GOLD_TRIM },
    variants: [
      { id: "khaki", name: "沙地卡其", palettes: { main: expKhaki, scarf: expMoss } },
      { id: "olive", name: "丛林橄榄", palettes: { main: expMoss, scarf: CRIMSON_ACC } }
    ],
    parts: [
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx;
          const ny = pose.neckY;
          ctx.pal("main");
          J(ctx, 13.6, { flare: 1.8 }, (s, nx, p) => p < 2.2 ? 0 : g.t(s, p > 9.4 ? -0.05 : 0.06));
          g.clip = true;
          if (pose.cos > 0.3) {
            const cx = gt(ctx);
            g.line(cx, ny + 3.0, cx, ny + 13.0, V);
            // Twin field chest pockets with brass snaps
            for (const dx of [-3.0, 3.0]) {
              g.rect(cx + dx - 1.3, ny + 4.8, 2.6, 2.8, (x, y) => y < ny + 5.6 ? 1 : 3);
              ctx.pal("gold");
              g.dot(cx + dx, ny + 5.7, 4);
              ctx.pal("main");
            }
          }
          g.clip = false;
          uo(ctx, 8.8, 10.6, "belt", "gold");
        }
      },
      ...Mt({ key: "main", cuffKey: "belt", r: 2.05, length: 0.65 }),
      // Triangular explorer neckerchief knotted at throat
      {
        layer: "scarf",
        draw: ctx => {
          const { g, pose } = ctx;
          const ny = pose.neckY;
          const cx = pose.torsoX(0) + pose.sin * 0.5;
          const rx = pose.torsoHalf + 1.0;
          ctx.pal("scarf");
          g.ellipse(cx, ny + 1.6, rx, 1.8, s => g.t(s, 0.05));
          if (pose.cos > 0.25) {
            const fx = gt(ctx);
            g.tri({ x: fx - 2.6, y: ny + 2.2 }, { x: fx + 2.6, y: ny + 2.2 }, { x: fx, y: ny + 6.4 }, 3);
            g.dot(fx, ny + 2.8, 4);
          } else if (pose.cos < -0.25) {
            g.tri({ x: cx - 3.0, y: ny + 2.0 }, { x: cx + 3.0, y: ny + 2.0 }, { x: cx, y: ny + 5.8 }, 2);
          }
        }
      }
    ]
  }, "expansion/top/costume_explorer");

  // --- 14. 暗夜怪盗装 (Phantom Thief Black Coat + Scarlet-Lined Cloak) ---
  const phBlack = k("cst-ph-black", "#06060c", "#161622", "#282a3a", "#464a62", "#7880a0");
  const phSilver = k("cst-ph-silver", "#1e2432", "#5c667c", "#a4b0c4", "#dce4f0", "#ffffff");
  Me({
    id: "top_costume_phantom",
    name: "暗夜怪盗装",
    slot: "top",
    palettes: { main: phBlack, lining: CRIMSON_ACC, shirt: IVORY_WHITE, silver: phSilver },
    variants: [
      { id: "scarlet", name: "猩红怪盗", palettes: { lining: CRIMSON_ACC } },
      { id: "cobalt",  name: "湛蓝怪盗", palettes: { lining: sailorBlue } }
    ],
    layerOverride: d => (d === "N" || d === "NE" ? { cape: Le.mantle - 1 } : {}),
    parts: [
      makeBackCape({ mainKey: "main", trimKey: "lining", liningKey: "lining", lenOffset: 6, extraWidth: 4.0 }),
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx;
          const ny = pose.neckY;
          ctx.pal("main");
          J(ctx, 13.8, { flare: 1.8 }, (s, nx, p) => p < 2.2 ? 0 : g.t(s, 0.04));
          g.clip = true;
          if (pose.cos > 0.3) {
            const cx = gt(ctx);
            // Crisp white cravat + scarlet lapel trim + diagonal silver watch chain
            ctx.pal("shirt");
            g.tri({ x: cx - 2.4, y: ny + 2.0 }, { x: cx + 2.4, y: ny + 2.0 }, { x: cx, y: ny + 6.4 }, 4);
            ctx.pal("lining");
            g.line(cx - 2.6, ny + 2.2, cx - 0.8, ny + 6.8, 3);
            g.line(cx + 2.6, ny + 2.2, cx + 0.8, ny + 6.8, 3);
            ctx.pal("silver");
            g.line(cx - 2.6, ny + 9.2, cx + 2.2, ny + 10.6, 4);
            g.dot(cx + 2.2, ny + 10.8, 4);
          }
          g.clip = false;
        }
      },
      // Sleek black sleeves with crisp white phantom-glove cuffs
      ...Mt({ key: "main", cuffKey: "shirt", r: 1.95 }),
      // Dramatic upturned phantom collar lined in scarlet
      {
        layer: "mantle",
        draw: ctx => {
          const { g, pose } = ctx;
          const ny = pose.neckY;
          const cx = pose.torsoX(0) - pose.sin * 0.6;
          const hw = pose.torsoHalf + 1.8;
          g.fill(cx - hw, ny - 2.4, cx + hw, ny + 3.2, (x, y) => {
            const nx = (x - cx) / hw;
            if (Math.abs(nx) > 1) return -1;
            const top = ny - 2.2 + 2.0 * (1 - nx * nx);
            const bot = ny + 2.6;
            if (y < top || y > bot) return -1;
            if (pose.cos > 0.25 && Math.abs(x - gt(ctx)) < 2.1) return -1;
            const isInner = y < top + 1.2 && pose.cos > -0.2;
            ctx.pal(isInner ? "lining" : "main");
            return g.t(nx * z + 0.4, isInner ? 0.25 : 0.05);
          });
        }
      }
    ]
  }, "expansion/top/costume_phantom");

  // --- 15. 甜点小厨师 (Pastry Chef Coat + Caramel Checkered Apron) ---
  const chefApron = k("cst-chef-apron", "#32180c", "#744020", "#b8703c", "#e4a468", "#ffe0b0");
  const chefBtn = k("cst-chef-btn", "#10121a", "#2e3240", "#545a6e", "#848ca2", "#bec6d8");
  Me({
    id: "top_costume_chef",
    name: "甜点小厨师",
    slot: "top",
    palettes: { main: IVORY_WHITE, apron: chefApron, tie: CRIMSON_ACC, btn: chefBtn },
    variants: [
      { id: "caramel", name: "焦糖围裙", palettes: { apron: chefApron, tie: CRIMSON_ACC } },
      { id: "berry",   name: "草莓围裙", palettes: { apron: kimonoSakura, tie: winterBerry } },
      { id: "matcha",  name: "抹茶围裙", palettes: { apron: expMoss, tie: GOLD_TRIM } }
    ],
    parts: [
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx;
          const ny = pose.neckY;
          drawExtendedSkirt(ctx, 0, 17.4, 2.2, (s, nx, p) => {
            if (p < 2.0) { ctx.pal("main"); return 2; }
            // Checkered caramel waist apron wrapping around hips
            if (p >= 8.6) {
              ctx.pal("apron");
              const check = ((Math.floor(nx * 6 + 10) + Math.floor(p * 0.8)) % 2 === 0);
              return g.t(s, check ? 0.2 : -0.15);
            }
            ctx.pal("main");
            return g.t(s, 0.12);
          });
          // Double-breasted chef buttons on front; apron bow tie on back!
          if (pose.cos > 0.3) {
            const cx = gt(ctx);
            g.clip = true;
            ctx.pal("btn");
            for (const row of [4.6, 6.6]) {
              g.dot(cx - 1.8, ny + row, 1);
              g.dot(cx + 1.8, ny + row, 1);
            }
            g.clip = false;
            // Cheerful red chef neckerchief knot at throat
            drawBow(ctx, cx, ny + 2.4, 0.78, "tie");
          } else if (pose.cos < -0.25) {
            drawBow(ctx, pose.torsoX(9) - pose.sin * 1.2, ny + 9.4, 0.9, "apron");
          }
        }
      },
      ...Mt({ key: "main", cuffKey: "apron", r: 2.0, length: 0.62 })
    ]
  }, "expansion/top/costume_chef");

  // --- 16. 星梦偶像装 (Starlight Stage Idol Jacket + Ruffled Pleated Dress) ---
  const idolViolet = k("cst-idol-vio", "#200e3c", "#52288e", "#8852d4", "#bc8cf8", "#ecdcff");
  const idolPink = k("cst-idol-pink", "#3e0c2c", "#8e2462", "#d8509a", "#f894c8", "#ffe0f0");
  Me({
    id: "top_costume_idol",
    name: "星梦偶像装",
    slot: "top",
    palettes: { main: idolViolet, accent: idolPink, shirt: IVORY_WHITE, gold: GOLD_TRIM },
    variants: [
      { id: "lavender", name: "星梦紫", palettes: { main: idolViolet, accent: idolPink } },
      { id: "sakura",   name: "甜心粉", palettes: { main: idolPink, accent: winterSky } },
      { id: "aqua",     name: "梦幻蓝", palettes: { main: winterSky, accent: idolViolet } }
    ],
    parts: [
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx;
          const ny = pose.neckY;
          drawExtendedSkirt(ctx, 0, 18.6, 5.4, (s, nx, p) => {
            if (p < 2.2) { ctx.pal("shirt"); return 3; }
            // Layered ruffled stage skirt below waist
            if (p > 9.4) {
              const distBot = 18.6 - p;
              const pleat = Math.sin(nx * 15) * 0.32;
              if (distBot < 1.6) { ctx.pal("shirt"); return g.t(s, 0.28); }
              if (distBot < 2.8) { ctx.pal("gold"); return g.t(s, 0.25); }
              if (p < 14.2) { ctx.pal("main"); return g.t(s + pleat, 0.08); }
              ctx.pal("accent");
              return g.t(s + pleat, 0.1);
            }
            // Gold stage waist belt
            if (p > 8.0) { ctx.pal("gold"); return g.t(s, 0.25); }
            // Cropped idol jacket over crisp white pleated blouse
            if (pose.cos > 0.25 && Math.abs(nx - pose.sin * 0.55) < 0.34) {
              ctx.pal("shirt");
              return g.t(s, 0.22);
            }
            ctx.pal("main");
            return g.t(s, 0.08);
          });
          // Radiant golden star brooch on chest + stage waist ribbon bow on back!
          if (pose.cos > 0.3) {
            const cx = gt(ctx);
            ctx.pal("gold");
            g.dot(cx, ny + 4.8, 4);
            g.dot(cx - 1.0, ny + 4.8, 3);
            g.dot(cx + 1.0, ny + 4.8, 3);
            g.dot(cx, ny + 3.8, 3);
            g.dot(cx, ny + 5.8, 3);
          } else if (pose.cos < -0.25) {
            drawBow(ctx, pose.torsoX(9) - pose.sin * 1.2, ny + 9.2, 1.15, "accent");
          }
        }
      },
      ...makePuffSleeves("main", "gold", 0.5, 2.3)
    ]
  }, "expansion/top/costume_idol");
}

registerCharacterExpansion({k,v,ie,Me,ho,Je,ze,We,Ao,i0,J,gt,Mt,Pe,ae,uo,ue,ut,wt,Le,z,mt,Q,V,_t,Et,pt,ct,xa,ma,Sa});
// --- END PROCEDURAL CHARACTER EXPANSION ---
// --- BEGIN PROCEDURAL EQUIPMENT EXPANSION ---
// Procedural Equipment Expansion for pixel-baker.js (v1.0 — Staged Expansion Pack)
// Adds:
//   - 17 new wearable weapons (slot: "weapon_main", strictly reusing existing hold
//     skeletons: down / shoulder / bow / up, with 4-phase bakeFx glow on all 9 Epic & Legendary weapons)
//   - 14 new wearable armors (slot: "top", id: top_<snake_case>, compatible with all
//     20 hairstyles & 18 eye colors, with 4-phase bakeFx glow on all 7 Epic & Legendary armors)
//
// Designed for injection alongside pixel_character_expansion.js by install_expansion_pack.py
// (requires extended bridge symbols: St, Z, lt, O, ye, jt, At, ko, Ut, xe, te, be, Qe, rt).
function registerEquipmentExpansion(C) {
  const {
    k, v, Me,
    J, gt, Mt, Pe, ae, uo, ue, ut, wt,
    z, Q, V, _t, Et, pt, ct,
    St, Z, lt, O, ye, jt, At, ko, Ut, xe, te, be, Qe, rt
  } = C;

  // =========================================================================
  // SHARED PALETTES (5-stop HD-2D pixel ramps matching pixel_baker_core.js)
  // =========================================================================
  const P = {
    wood:    k("eq-wood",    "#1a0e06", "#4e2e14", "#86562a", "#bc8644", "#e8b874"),
    woodL:   k("eq-woodL",   "#26180c", "#6c4824", "#a87842", "#d8aa6a", "#f8dcb0"),
    iron:    k("eq-iron",    "#141820", "#465060", "#7c889c", "#b8c4d6", "#eef4fc"),
    silver:  k("eq-silver",  "#1c2234", "#5a6680", "#9eaac0", "#dae4f4", "#ffffff"),
    gold:    k("eq-gold",    "#3c2206", "#8c5c14", "#d69e2c", "#f8d464", "#fff6be"),
    bronze:  k("eq-bronze",  "#2a1608", "#683c18", "#a46830", "#d89c54", "#f8d494"),
    leather: k("eq-leather", "#180c06", "#462814", "#784826", "#ae723e", "#dda468"),
    cream:   k("eq-cream",   "#3c3426", "#82745c", "#bcaf92", "#e6dcc2", "#faf4e4"),
    olive:   k("eq-olive",   "#12200c", "#2e4e1e", "#4e7c34", "#7eb056", "#bce088"),
    leaf:    k("eq-leaf",    "#0c2810", "#1e6028", "#3c9e42", "#78d864", "#c4fc98"),
    emerald: k("eq-emerald", "#062a18", "#106c42", "#26b672", "#6ef0a6", "#d8ffe8"),
    ice:     k("eq-ice",     "#0c2a54", "#226cb8", "#4eb2f2", "#a2e4ff", "#f2ffff"),
    teal:    k("eq-teal",    "#0a2a34", "#1a6274", "#32a4b4", "#70dce0", "#ccfcfc"),
    blue:    k("eq-blue",    "#0a183c", "#1c3c86", "#3468cc", "#6aa6f2", "#c4e4ff"),
    indigo:  k("eq-indigo",  "#0c0e2c", "#202664", "#3c469e", "#6e7cd4", "#b8c6fa"),
    purple:  k("eq-purple",  "#1c0c38", "#462280", "#7a44c4", "#b67ef2", "#ebd4ff"),
    obsid:   k("eq-obsid",   "#0c0b14", "#242234", "#44405c", "#747094", "#b4b0cc"),
    crimson: k("eq-crimson", "#2e060c", "#741420", "#be2836", "#f05e5c", "#ffb4a8"),
    fire:    k("eq-fire",    "#6a1408", "#c84214", "#f68e28", "#ffd45c", "#fff8cc"),
    white:   k("eq-white",   "#384056", "#848ea8", "#c6cee0", "#ecf0f8", "#ffffff"),
    string:  k("eq-string",  "#38362a", "#8a846c", "#c8c2a8", "#ece8d4", "#ffffff"),
    fxIce:   k("eq-fx-ice",  "#1854a8", "#42a4f0", "#8ce0ff", "#d4f8ff", "#ffffff"),
    fxWind:  k("eq-fx-wind", "#146674", "#34b8c4", "#7ef0f0", "#ccfefe", "#ffffff"),
    fxLeaf:  k("eq-fx-leaf", "#10582c", "#28a856", "#66e888", "#beffc8", "#f0fff2"),
    fxPurp:  k("eq-fx-purp", "#3c1878", "#7c3ed0", "#ba7eff", "#e4c4ff", "#fff4ff"),
    fxFire:  k("eq-fx-fire", "#7a1c0c", "#d04a18", "#f6902c", "#ffd060", "#fff6c8"),
    fxGold:  k("eq-fx-gold", "#7c4808", "#cc8818", "#f8c83c", "#ffea88", "#ffffdc"),
    fxHoly:  k("eq-fx-holy", "#4c5c94", "#98b8ec", "#d8ecff", "#f6fbff", "#ffffff")
  };

  // =========================================================================
  // SHARED WEAPON / ARMOR DRAWING HELPERS
  // =========================================================================

  // Reusable bow renderer with configurable limb/wrap/string/arrow palettes & curve scale
  function makeBowDraw(opts) {
    const { halfLen = 13, recurve = 0, wingTips = false, boltGlow = false } = opts;
    return function drawBow(ctx, solidPass) {
      const h = lt(ctx);
      if (!h) return;
      const { g, pose } = ctx;
      const r = pose.sin, i = pose.cos * 0.35;
      const sx = -h.dy, sy = h.dx;
      const dot = sx * r + sy * i;
      const sign = dot >= 0 ? 1 : -1;
      const bend = 2.5 * Math.max(0.35, Math.min(1, Math.abs(dot) * 1.4));
      const ptAt = t => {
        const u = t / halfLen;
        const off = -sign * bend * (u * u - recurve * Math.pow(Math.abs(u), 3) * 0.45);
        return { x: h.x + h.dx * t * h.k + sx * off, y: h.y + h.dy * t * h.k + sy * off };
      };
      const pts = Array.from({ length: 13 }, (_, idx) => ptAt(-halfLen + idx * 2 * halfLen / 12));
      if (solidPass) {
        ctx.pal("wood");
        g.ribbon(pts, t => 1.0 - 0.42 * Math.abs(t - 0.5) * 2, (t, n) => n < -0.3 ? 3 : n > 0.4 ? 1 : g.t(t) > 3 ? 4 : 2);
        ctx.pal("wrap");
        g.ribbon([ptAt(-1.8), ptAt(0), ptAt(1.8)], () => 1.1, (t, n) => n < 0 ? 3 : 1);
        if (wingTips) {
          ctx.pal("trim");
          for (const endT of [-halfLen, halfLen]) {
            const p = ptAt(endT);
            g.dot(p.x + sx * sign * 1.4, p.y + sy * sign * 1.4, 4);
            g.dot(p.x + sx * sign * 2.2, p.y + sy * sign * 2.2, 3);
          }
        }
        return;
      }
      const pTop = ptAt(halfLen), pBot = ptAt(-halfLen);
      const drawing = pose.fx === "arrow" && pose.anim === "shoot";
      const hr = pose.handR;
      ctx.pal("string");
      if (drawing) {
        g.line(pTop.x, pTop.y, hr.x, hr.y + 0.4, 3);
        g.line(pBot.x, pBot.y, hr.x, hr.y + 0.4, 2);
        const ax = pose.sin, ay = pose.cos * 0.35 + 0.02;
        const len = Math.hypot(ax, ay) || 1;
        const ux = ax / len, uy = ay / len;
        const reach = 15 * (0.4 + 0.6 * Math.min(1, len));
        const tx = hr.x + ux * reach, ty = hr.y + 0.4 + uy * reach;
        ctx.pal("arrow");
        g.line(hr.x, hr.y + 0.4, tx, ty, boltGlow ? 4 : 3);
        g.dot(tx, ty, 4);
        ctx.pal("fletch");
        g.dot(hr.x + ux * 1.2, hr.y + 0.4 + uy * 1.2 - 0.6, 3);
        g.dot(hr.x + ux * 1.2, hr.y + 0.4 + uy * 1.2 + 0.6, 2);
      } else {
        g.line(pTop.x, pTop.y, pBot.x, pBot.y, 2);
      }
    };
  }

  // Reusable flowing armor back cape (matches pixel_character_expansion.js)
  function makeArmorCape(opts) {
    const {
      mainKey = "cloth", trimKey = "trim", liningKey = null,
      lenOffset = 7.5, extraWidth = 3.2, asymmetric = false, starry = false
    } = opts;
    return {
      layer: "cape",
      draw: ctx => {
        const { g, pose } = ctx;
        const { sin, cos } = pose;
        const showingBack = cos < 0.3;
        const walking = pose.anim === "walk";
        const sway = walking ? Math.sin(pose.phase + 1) : 0;
        const topW = (asymmetric ? 4.8 : 6.0) * Math.abs(cos) + 2.8 * Math.abs(sin) + 1.0;
        const botW = topW + extraWidth;
        const cxBase = pose.torsoX(3) - sin * 3.4 + (asymmetric ? -cos * 2.2 : 0);
        const y0 = pose.neckY - 0.2;
        const y1 = Et - lenOffset;
        const folds = 2.0 + Math.abs(cos) * 1.1;
        g.grit = 0.18;
        g.fill(cxBase - botW - 5, y0, cxBase + botW + 5, y1 + 2, (x, y) => {
          const p = Math.min(1, (y - y0) / (y1 - y0));
          if (p < 0) return -1;
          const cx = cxBase + sway * p * 1.5 - sin * p * 2.1;
          const hw = topW + (botW - topW) * p;
          const nx = (x - cx) / hw;
          if (Math.abs(nx) > 1) return -1;
          const wave = nx * folds * Math.PI + p * sway * 0.7;
          const hem = y1 + 0.7 * Math.sin(wave + 0.5);
          if (y > hem) return -1;
          const ridge = Math.sin(wave + 0.8) * Math.min(1, p * 1.6);
          if (!showingBack) {
            if (liningKey) { ctx.pal(liningKey); return g.t(0.1 + ridge * 0.4, -0.2); }
            ctx.pal(mainKey); return ridge > 0.3 ? 1 : 0;
          }
          let shade = 0.18 + nx * z * 0.85 + ridge * 0.65;
          if (p < 0.12) shade -= 0.5;
          const fromHem = hem - y;
          if (trimKey && fromHem > 0.9 && fromHem < 2.3) {
            ctx.pal(trimKey); return g.t(shade, 0.25);
          }
          if (starry && ((Math.floor(x * 1.3) * 17 + Math.floor(y * 1.3) * 31) % 29 === 0) && p > 0.22) {
            ctx.pal(trimKey); return 4;
          }
          ctx.pal(mainKey);
          return g.t(shade);
        });
      }
    };
  }

  // Reusable armor 4-phase shoulder/chest subtle glow (bakeFx)
  function makeArmorGlow(palKey, style = "shoulders") {
    return xe(ctx => {
      const { pose, g } = ctx;
      ctx.pal(palKey);
      g.grit = 0;
      if (style === "shoulders" || style === "holy") {
        for (const side of ["L", "R"]) {
          const arm = wt(ctx, side);
          const active = (ctx.phase % 2 === 0) === (side === "L");
          if (!arm.hand.front && Math.abs(pose.cos) < 0.3) continue;
          g.dot(arm.shoulder.x, arm.shoulder.y - 0.5, active ? 4 : 3);
          if (active) {
            const lift = 1.8 + (ctx.phase >> 1) * 1.3;
            te(ctx, arm.shoulder.x + (side === "L" ? -0.8 : 0.8) * pose.cos, arm.shoulder.y - lift, 1);
          }
        }
      }
      if (style === "flame") {
        for (const side of ["L", "R"]) {
          const arm = wt(ctx, side);
          if (!arm.hand.front && Math.abs(pose.cos) < 0.3) continue;
          const phaseOff = side === "L" ? ctx.phase : (ctx.phase + 2) % 4;
          be(ctx, arm.shoulder.x, arm.shoulder.y - 1.2 - phaseOff * 0.4, 2.0 + (phaseOff % 2) * 0.7);
        }
      }
      if (style === "stars" || style === "holy") {
        if (pose.cos > 0.2) {
          const cx = gt(ctx), cy = pose.neckY + 5.5;
          const ang = ctx.phase * Math.PI * 0.5;
          g.dot(cx + Math.cos(ang) * 4.2, cy + Math.sin(ang) * 2.2, 4);
          g.dot(cx - Math.cos(ang) * 3.8, cy - Math.sin(ang) * 2.0, 3);
        }
      }
    }, "arm_front");
  }

  // =========================================================================
  // PART A: 17 NEW WEARABLE WEAPONS (strictly hold: down / shoulder / bow / up)
  // =========================================================================

  // 1. 橡木弹弓 (oakSlingshot, Common, hold: bow)
  Me({
    id: "weapon_oak_slingshot", name: "橡木弹弓", slot: "weapon_main", hold: "bow", gameItem: "oakSlingshot",
    palettes: { wood: P.wood, wrap: P.leaf, band: P.leather, stone: P.iron },
    parts: [{
      layer: "weapon",
      draw: ctx => {
        const h = lt(ctx); if (!h) return;
        const { g, pose } = ctx;
        ctx.pal("wood");
        Z(ctx, h, -3.5, 4.5, 1.1, (s, n) => n < 0 ? 3 : 1);
        ctx.pal("wrap");
        Z(ctx, h, -1.8, 2.2, 1.25, (s, n) => n < 0 ? 3 : 2);
        // Y-fork branches
        const base = O(h, 4.2, 0), forkL = O(h, 11.2, -4.2), forkR = O(h, 11.2, 4.2);
        ctx.pal("wood");
        g.capsule(base.x, base.y, forkL.x, forkL.y, 1.0, 0.85, s => s > 0 ? 3 : 1);
        g.capsule(base.x, base.y, forkR.x, forkR.y, 1.0, 0.85, s => s > 0 ? 3 : 1);
        // Elastic leather band + pebble when aiming
        ctx.pal("band");
        const pull = pose.fx === "arrow" && pose.anim === "shoot" ? pose.handR : O(h, 9.6, 0);
        g.line(forkL.x, forkL.y, pull.x, pull.y, 2);
        g.line(forkR.x, forkR.y, pull.x, pull.y, 2);
        ctx.pal("stone");
        g.ellipse(pull.x, pull.y, 1.5, 1.5, s => s > 0.2 ? 4 : 2);
      }
    }]
  }, "expansion/weapon/oak_slingshot");

  // 2. 橡木法杖 (woodenStaff, Common, hold: up)
  Me({
    id: "weapon_wooden_staff", name: "橡木法杖", slot: "weapon_main", hold: "up", gameItem: "woodenStaff",
    palettes: { wood: P.woodL, leaf: P.leaf, gem: P.fxLeaf, fx: P.fxLeaf },
    parts: [{
      layer: "weapon",
      draw: ctx => {
        const h = lt(ctx); if (!h) return;
        const { g } = ctx;
        ctx.pal("wood");
        Z(ctx, h, -10, 31, 0.82, (s, n) => n < -0.1 ? 3 : n > 0.4 ? 1 : 2);
        const top = O(h, 31, 0), f1 = O(h, 36.5, -2.8), f2 = O(h, 36.5, 2.8);
        g.capsule(top.x, top.y, f1.x, f1.y, 0.8, 0.55, s => s > 0 ? 3 : 1);
        g.capsule(top.x, top.y, f2.x, f2.y, 0.8, 0.55, s => s > 0 ? 3 : 1);
        ctx.pal("leaf");
        const lf1 = O(h, 28, -2.5), lf2 = O(h, 26.5, 2.4);
        g.ellipse(lf1.x, lf1.y, 1.9, 1.1, s => s > 0 ? 3 : 2);
        g.ellipse(lf2.x, lf2.y, 1.8, 1.0, s => s > 0 ? 3 : 1);
        ctx.pal("gem");
        const orb = O(h, 36.5, 0);
        ko(ctx, orb.x, orb.y, 2.6);
      }
    }, At(h => O(h, 36.5), "fx", 0.9)]
  }, "expansion/weapon/wooden_staff");

  // 3. 铁制双匕 (ironDagger, Common, hold: down)
  Me({
    id: "weapon_iron_dagger", name: "铁制双匕", slot: "weapon_main", hold: "down", gameItem: "ironDagger",
    palettes: { blade: P.iron, hilt: P.silver, grip: P.blue, fx: P.fxHoly },
    parts: [{
      layer: "weapon",
      draw: ctx => St(ctx, { from: 2.8, to: 15.5, half: 1.05, tip: 4.0, curve: -1.1, core: "fuller", grip: 2.6, guard: [2.9, 1.1, 0.6], pommel: 1.0 })
    }, jt(4, 17)]
  }, "expansion/weapon/iron_dagger");

  // 4. 霜晶魔杖 (frostWand, Rare, hold: up)
  Me({
    id: "weapon_frost_wand", name: "霜晶魔杖", slot: "weapon_main", hold: "up", gameItem: "frostWand",
    palettes: { shaft: P.silver, gem: P.ice, fx: P.fxIce },
    parts: [{
      layer: "weapon",
      draw: ctx => {
        const h = lt(ctx); if (!h) return;
        const { g } = ctx;
        ctx.pal("shaft");
        Z(ctx, h, -9, 31, 0.75, (s, n) => n < 0 ? 3 : 1);
        const c = O(h, 36.0, 0);
        ctx.pal("gem");
        // Hexagonal snowflake crystal
        for (let i = 0; i < 6; i++) {
          const a = i * Math.PI / 3;
          g.line(c.x, c.y, c.x + Math.cos(a) * 5.2, c.y + Math.sin(a) * 5.2, i % 2 === 0 ? 4 : 3);
        }
        ko(ctx, c.x, c.y, 2.8);
      }
    }, At(h => O(h, 36.0), "fx", 1.0)]
  }, "expansion/weapon/frost_wand");

  // 5. 骑士战戟 (knightHalberd, Rare, hold: shoulder)
  Me({
    id: "weapon_knight_halberd", name: "骑士战戟", slot: "weapon_main", hold: "shoulder", gameItem: "knightHalberd",
    palettes: { shaft: P.wood, blade: P.silver, trim: P.gold, tassel: P.crimson, fx: P.fxHoly },
    parts: [{
      layer: "weapon",
      draw: ctx => {
        const h = lt(ctx); if (!h) return;
        const { g } = ctx;
        ctx.pal("shaft");
        Z(ctx, h, -7, 29, 0.82, (s, n) => n < 0 ? 3 : 1);
        // Spear point
        ctx.pal("blade");
        Z(ctx, h, 28, 36.5, 1.5, (s, n) => {
          const w = 1.45 * (1 - (s - 28) / 8.5);
          return Math.abs(n) > w ? -1 : n < 0 ? 4 : 2;
        });
        // Crescent axe blade on side
        Z(ctx, h, 22, 31, 6.2, (s, n) => {
          if (n > -0.8 || n < -5.8) return -1;
          const ds = (s - 26.5) / 4.6;
          const dn = (n + 1.0) / 4.8;
          if (ds * ds + dn * dn > 1.0) return -1;
          return n < -4.2 ? 4 : ds < 0 ? 3 : 2;
        });
        // Back spike & crimson tassel
        const collar = O(h, 24, 0), spike = O(h, 26, 4.0), tas = O(h, 21.5, 2.2);
        g.line(collar.x, collar.y, spike.x, spike.y, 3);
        ctx.pal("trim");
        g.ellipse(collar.x, collar.y, 1.5, 1.5, s => s > 0 ? 4 : 2);
        ctx.pal("tassel");
        g.capsule(collar.x, collar.y, tas.x, tas.y + 3.2, 0.9, 1.2, s => s > 0 ? 3 : 1);
      }
    }, jt(10, 36), At(h => O(h, 30), "fx", 0.9)]
  }, "expansion/weapon/knight_halberd");

  // 6. 炎铁巨斧 (flameAxe, Epic, hold: shoulder, + bakeFx flame!)
  Me({
    id: "weapon_flame_axe", name: "炎铁巨斧", slot: "weapon_main", hold: "shoulder", gameItem: "flameAxe",
    palettes: { shaft: P.wood, gold: P.gold, head: P.obsid, fire: P.fire, fx: P.fxFire },
    parts: [{
      layer: "weapon",
      draw: ctx => {
        const h = lt(ctx); if (!h) return;
        ctx.pal("shaft");
        Z(ctx, h, -6, 28, 0.95, (s, n) => n < 0 ? 3 : 1);
        ctx.pal("gold");
        Z(ctx, h, 18, 20, 1.35, (s, n) => n < 0 ? 4 : 2);
        // Double-bit obsidian axe blades with blazing molten outer edge
        Z(ctx, h, 19.5, 31.5, 7.2, (s, n) => {
          const an = Math.abs(n);
          if (an < 0.7 || an > 6.8) return -1;
          const span = 2.1 + an * 0.52;
          if (Math.abs(s - 25.5) > span) return -1;
          if (an > 5.0) { ctx.pal("fire"); return an > 5.9 ? 4 : 3; }
          ctx.pal("head");
          return s > 25.5 ? 3 : 1;
        });
      }
    }, jt(10, 34), At(h => O(h, 26), "fx", 1.1),
      Ut((ctx, h) => {
        for (let e = 0; e < 4; e++) {
          const s = 21 + e * 2.8, side = (e % 2 === 0 ? -1 : 1) * (5.6 + ((ctx.phase + e) % 2) * 0.8);
          const p = O(h, s, side);
          be(ctx, p.x, p.y, 1.8 + ((ctx.phase + e) % 3) * 0.65);
        }
      })
    ]
  }, "expansion/weapon/flame_axe");

  // 7. 迅雷手弩 (thunderCrossbow, Epic, hold: bow, + bakeFx lightning!)
  Me({
    id: "weapon_thunder_crossbow", name: "迅雷手弩", slot: "weapon_main", hold: "bow", gameItem: "thunderCrossbow",
    palettes: { stock: P.purple, trim: P.gold, bolt: P.ice, fx: P.fxIce },
    parts: [{
      layer: "weapon",
      draw: ctx => {
        const h = lt(ctx); if (!h) return;
        const { g } = ctx;
        ctx.pal("stock");
        Z(ctx, h, -4, 11, 1.3, (s, n) => n < 0 ? 3 : 1);
        // Winged prod cross-arms
        const c = O(h, 8.5, 0), wL = O(h, 5.5, -8.5), wR = O(h, 5.5, 8.5);
        ctx.pal("trim");
        g.capsule(c.x, c.y, wL.x, wL.y, 1.2, 0.8, s => s > 0 ? 4 : 2);
        g.capsule(c.x, c.y, wR.x, wR.y, 1.2, 0.8, s => s > 0 ? 4 : 2);
        // Glowing lightning string & loaded thunder crystal bolt
        ctx.pal("bolt");
        const tail = O(h, 1.5, 0), tip = O(h, 14.5, 0);
        g.line(wL.x, wL.y, tail.x, tail.y, 3);
        g.line(wR.x, wR.y, tail.x, tail.y, 3);
        g.line(tail.x, tail.y, tip.x, tip.y, 4);
        g.dot(tip.x, tip.y, 4);
      }
    }, Ut((ctx, h) => {
      const p1 = O(h, 13.5, (ctx.phase % 2 ? -1.4 : 1.4));
      const p2 = O(h, 6.0, ctx.phase < 2 ? -8.2 : 8.2);
      te(ctx, p1.x, p1.y, 1);
      ctx.g.dot(p2.x, p2.y, 4);
    })]
  }, "expansion/weapon/thunder_crossbow");

  // 8. 翡翠长杖 (emeraldScepter, Epic, hold: up, + bakeFx emerald!)
  Me({
    id: "weapon_emerald_scepter", name: "翡翠长杖", slot: "weapon_main", hold: "up", gameItem: "emeraldScepter",
    palettes: { gold: P.gold, vine: P.leaf, gem: P.emerald, fx: P.fxLeaf },
    parts: [{
      layer: "weapon",
      draw: ctx => {
        const h = lt(ctx); if (!h) return;
        const { g } = ctx;
        ctx.pal("gold");
        Z(ctx, h, -10, 32, 0.85, (s, n) => n < 0 ? 3 : 1);
        ctx.pal("vine");
        Z(ctx, h, -6, 30, 1.05, (s, n) => Math.abs(n - Math.sin(s * 0.7) * 0.8) < 0.42 ? 3 : -1);
        const orb = O(h, 37.5, 0);
        ctx.pal("gold");
        g.ellipse(orb.x, orb.y + 1.2, 4.4, 4.4, (s, x, y) => Math.hypot(x - orb.x, y - (orb.y + 1.2)) > 3.2 && y > orb.y - 1 ? 3 : -1);
        ctx.pal("gem");
        ko(ctx, orb.x, orb.y, 3.1);
      }
    }, At(h => O(h, 37.5), "fx", 1.15),
      Ut((ctx, h) => {
        const orb = O(h, 37.5, 0);
        Qe(ctx, orb.x, orb.y, 6, 7.8 + (ctx.phase % 2) * 1.8, ctx.phase * Math.PI / 8);
        const a = ctx.phase * Math.PI * 0.5;
        te(ctx, orb.x + Math.cos(a) * 5.2, orb.y + Math.sin(a) * 4.6, 1);
      })
    ]
  }, "expansion/weapon/emerald_scepter");

  // 9. 暗影双刃 (shadowTwinblades, Epic, hold: down, + bakeFx purple mist!)
  Me({
    id: "weapon_shadow_twinblades", name: "暗影双刃", slot: "weapon_main", hold: "down", gameItem: "shadowTwinblades",
    palettes: { blade: P.purple, hilt: P.obsid, grip: P.indigo, gem: P.fxPurp, fx: P.fxPurp },
    parts: [{
      layer: "weapon",
      draw: ctx => St(ctx, { from: 3.0, to: 21.0, half: 1.5, tip: 5.5, curve: -2.0, core: "glow", grip: 2.8, guard: [4.2, 1.3, 1.6], pommel: 1.2 }, true)
    }, jt(5, 23), At(h => O(h, 17), "fx", 1.0),
      Ut((ctx, h) => {
        [O(h, 8, -2.5), O(h, 13, 2.2), O(h, 18, -1.8), O(h, 11, -3.0)].forEach((p, idx) =>
          idx === ctx.phase ? te(ctx, p.x, p.y, 2) : ctx.g.dot(p.x, p.y, (idx + ctx.phase) % 2 ? 4 : 3)
        );
      })
    ]
  }, "expansion/weapon/shadow_twinblades");

  // 10. 破晓圣剑 (sunbreakerBlade, Legendary, hold: shoulder, + bakeFx sun rays!)
  Me({
    id: "weapon_sunbreaker_blade", name: "破晓圣剑", slot: "weapon_main", hold: "shoulder", gameItem: "sunbreakerBlade",
    palettes: { blade: P.white, hilt: P.gold, grip: P.crimson, gem: P.fire, fx: P.fxGold },
    parts: [{
      layer: "weapon",
      draw: ctx => St(ctx, { from: 4.4, to: 33.0, half: 2.35, tip: 5.2, core: "glow", grip: 5.0, guard: [5.4, 1.8, 1.5], pommel: 1.6 }, true)
    }, jt(9, 36), At(h => O(h, 29), "fx", 1.2),
      Ut((ctx, h) => {
        const mid = O(h, 22, 0), tip = O(h, 32, 0);
        Qe(ctx, tip.x, tip.y, 6, 6.5 + (ctx.phase % 2) * 1.8, ctx.phase * Math.PI / 8);
        te(ctx, mid.x, mid.y + (ctx.phase % 2 ? -2.4 : 2.4), 1);
      })
    ]
  }, "expansion/weapon/sunbreaker_blade");

  // 11. 星陨长弓 (astralGreatbow, Legendary, hold: bow, + bakeFx starlight!)
  const drawAstralBow = makeBowDraw({ halfLen: 15, recurve: 0.75, wingTips: true, boltGlow: true });
  Me({
    id: "weapon_astral_greatbow", name: "星陨长弓", slot: "weapon_main", hold: "bow", gameItem: "astralGreatbow",
    palettes: { wood: P.indigo, wrap: P.gold, trim: P.gold, string: P.fxHoly, arrow: P.fxGold, fletch: P.fxGold, fx: P.fxGold },
    parts: [
      { layer: "weapon", draw: ctx => drawAstralBow(ctx, true) },
      { layer: "weapon", outline: false, draw: ctx => drawAstralBow(ctx, false) },
      Ut((ctx, h) => {
        const spots = [O(h, 12, -2.5), O(h, -12, -2.5), O(h, 5, 2.2), O(h, -5, 2.2)];
        spots.forEach((p, idx) => idx === ctx.phase ? te(ctx, p.x, p.y, 2) : ctx.g.dot(p.x, p.y, 4));
      })
    ]
  }, "expansion/weapon/astral_greatbow");

  // 12. 林野木枪 (wildwoodSpear, Common, Set 1, hold: down)
  Me({
    id: "weapon_wildwood_spear", name: "林野木枪", slot: "weapon_main", hold: "down", gameItem: "wildwoodSpear",
    palettes: { shaft: P.wood, vine: P.leaf, blade: P.iron, fx: P.fxLeaf },
    parts: [{
      layer: "weapon",
      draw: ctx => {
        const h = lt(ctx); if (!h) return;
        const { g } = ctx;
        ctx.pal("shaft");
        Z(ctx, h, -6, 17, 0.72, (s, n) => n < 0 ? 3 : 1);
        ctx.pal("blade");
        Z(ctx, h, 16.5, 24.5, 1.75, (s, n) => {
          const t = (s - 16.5) / 8.0;
          const w = Math.sin(t * Math.PI) * 1.65 + (1 - t) * 0.4;
          return Math.abs(n) > w ? -1 : n < 0 ? 4 : 2;
        });
        ctx.pal("vine");
        const lf1 = O(h, 15.5, -2.1), lf2 = O(h, 15.5, 2.1);
        g.ellipse(lf1.x, lf1.y, 1.8, 1.0, s => s > 0 ? 3 : 2);
        g.ellipse(lf2.x, lf2.y, 1.8, 1.0, s => s > 0 ? 3 : 1);
      }
    }, jt(6, 26)]
  }, "expansion/weapon/wildwood_spear");

  // 13. 疾风长弓 (galeLongbow, Rare, Set 2, hold: bow)
  const drawGaleBow = makeBowDraw({ halfLen: 14.5, recurve: 0.9, wingTips: true });
  Me({
    id: "weapon_gale_longbow", name: "疾风长弓", slot: "weapon_main", hold: "bow", gameItem: "galeLongbow",
    palettes: { wood: P.teal, wrap: P.silver, trim: P.white, string: P.fxIce, arrow: P.fxWind, fletch: P.white },
    parts: [
      { layer: "weapon", draw: ctx => drawGaleBow(ctx, true) },
      { layer: "weapon", outline: false, draw: ctx => drawGaleBow(ctx, false) }
    ]
  }, "expansion/weapon/gale_longbow");

  // 14. 橡木战锤 (oakHammer, Rare, Set 3, hold: shoulder)
  Me({
    id: "weapon_oak_hammer", name: "橡木战锤", slot: "weapon_main", hold: "shoulder", gameItem: "oakHammer",
    palettes: { shaft: P.wood, bronze: P.bronze, rune: P.fxLeaf, fx: P.fxLeaf },
    parts: [{
      layer: "weapon",
      draw: ctx => {
        const h = lt(ctx); if (!h) return;
        ctx.pal("shaft");
        Z(ctx, h, -6, 26, 0.95, (s, n) => n < 0 ? 3 : 1);
        // Chunky oak-and-bronze warhammer head
        Z(ctx, h, 21.5, 30.0, 5.8, (s, n) => {
          const an = Math.abs(n);
          if (an > 5.4) return -1;
          if (an > 3.8 || s < 22.6 || s > 28.9) { ctx.pal("bronze"); return n < 0 ? 4 : 2; }
          if (Math.abs(s - 25.8) < 1.1 && an < 1.6) { ctx.pal("rune"); return 4; }
          ctx.pal("shaft");
          return n < 0 ? 3 : 1;
        });
      }
    }, jt(9, 32), At(h => O(h, 26), "fx", 0.95)]
  }, "expansion/weapon/oak_hammer");

  // 15. 秘焰法杖 (emberStaff, Epic, Set 5, hold: up, + bakeFx fire!)
  Me({
    id: "weapon_ember_staff", name: "秘焰法杖", slot: "weapon_main", hold: "up", gameItem: "emberStaff",
    palettes: { shaft: P.purple, gold: P.gold, gem: P.fire, fx: P.fxFire },
    parts: [{
      layer: "weapon",
      draw: ctx => {
        const h = lt(ctx); if (!h) return;
        const { g } = ctx;
        ctx.pal("shaft");
        Z(ctx, h, -10, 31, 0.82, (s, n) => n < 0 ? 3 : 1);
        ctx.pal("gold");
        Z(ctx, h, 29.5, 31.8, 1.4, (s, n) => n < 0 ? 4 : 2);
        const c = O(h, 37.5, 0);
        // Fiery golden ring cradling flame crystal
        g.fill(c.x - 6, c.y - 6, c.x + 6, c.y + 6, (x, y) => {
          const r = Math.hypot(x - c.x, y - c.y);
          if (Math.abs(r - 4.7) > 0.95) return -1;
          return y < c.y ? 4 : 2;
        });
        ctx.pal("gem");
        ko(ctx, c.x, c.y, 2.8);
      }
    }, At(h => O(h, 37.5), "fx", 1.2),
      Ut((ctx, h) => {
        const c = O(h, 37.5, 0);
        Qe(ctx, c.x, c.y, 6, 8.2 + (ctx.phase % 2) * 1.8, ctx.phase * Math.PI / 8);
        be(ctx, c.x, c.y - 2.2, 3.0 + (ctx.phase % 2) * 1.1);
      })
    ]
  }, "expansion/weapon/ember_staff");

  // 16. 苍穹圣枪 (aegisLance, Legendary, Set 7, hold: shoulder, + bakeFx seraph glow!)
  Me({
    id: "weapon_aegis_lance", name: "苍穹圣枪", slot: "weapon_main", hold: "shoulder", gameItem: "aegisLance",
    palettes: { shaft: P.white, gold: P.gold, tip: P.ice, fx: P.fxGold },
    parts: [{
      layer: "weapon",
      draw: ctx => {
        const h = lt(ctx); if (!h) return;
        const { g } = ctx;
        ctx.pal("gold");
        Z(ctx, h, -5, 4.5, 1.0, (s, n) => n < 0 ? 4 : 2);
        // Tapered spiral platinum lance shaft + ice-blue holy point
        Z(ctx, h, 4.5, 35.5, 2.3, (s, n) => {
          const t = (s - 4.5) / 31.0;
          const w = 2.15 * (1 - t * 0.78);
          if (Math.abs(n) > w) return -1;
          if (t > 0.72) { ctx.pal("tip"); return n <= 0 ? 4 : 3; }
          if (Math.floor(s * 0.75 + n * 0.5) % 2 === 0) { ctx.pal("gold"); return n < 0 ? 4 : 2; }
          ctx.pal("shaft"); return n < 0 ? 4 : 2;
        });
        // Unfurled golden angel-wing guard
        const base = O(h, 5.2, 0);
        ctx.pal("gold");
        for (const side of [-1, 1]) {
          const tip = O(h, 11.5, side * 5.6);
          g.capsule(base.x, base.y, tip.x, tip.y, 1.3, 0.75, s => s > 0 ? 4 : 2);
        }
      }
    }, jt(10, 37), At(h => O(h, 33), "fx", 1.2),
      Ut((ctx, h) => {
        const tip = O(h, 34.0, 0);
        Qe(ctx, tip.x, tip.y, 8, 7.5 + (ctx.phase % 2) * 1.8, ctx.phase * Math.PI / 12);
        te(ctx, tip.x, tip.y, 1);
      })
    ]
  }, "expansion/weapon/aegis_lance");

  // 17. 星辰魔典 (astralCodex, Legendary, Set 8, hold: up, + bakeFx orbiting astrolabe!)
  Me({
    id: "weapon_astral_codex", name: "星辰魔典", slot: "weapon_main", hold: "up", gameItem: "astralCodex",
    palettes: { cover: P.indigo, gold: P.gold, page: P.cream, fx: P.fxGold },
    parts: [{
      layer: "weapon",
      draw: ctx => {
        const h = lt(ctx); if (!h) return;
        const { g } = ctx;
        const c = O(h, 11.5, 0);
        // Levitating open deep-blue & gold grimoire
        ctx.pal("cover");
        g.fill(c.x - 6.5, c.y - 4.2, c.x + 6.5, c.y + 4.4, (x, y) => {
          const dx = x - c.x, dy = y - c.y;
          const arch = Math.cos(dx / 6.5 * 1.2) * 1.1;
          if (Math.abs(dx) > 6.0 || dy < -3.4 - arch || dy > 3.5 - arch * 0.5) return -1;
          if (Math.abs(dx) > 5.0 || dy > 2.4 - arch * 0.5) { ctx.pal("gold"); return dx < 0 ? 4 : 2; }
          if (Math.abs(dx) < 0.7) { ctx.pal("cover"); return 1; }
          ctx.pal("page");
          return dx < 0 ? 4 : 3;
        });
        // Tiny glowing rune script
        ctx.pal("cover");
        g.line(c.x - 4.0, c.y - 1.0, c.x - 1.5, c.y - 1.0, 3);
        g.line(c.x + 1.5, c.y - 1.0, c.x + 4.0, c.y - 1.0, 3);
        // Floating golden star above pages
        ctx.pal("gold");
        g.dot(c.x, c.y - 6.2, 4);
      }
    }, At(h => O(h, 16), "fx", 1.2),
      Ut((ctx, h) => {
        const c = O(h, 17.5, 0);
        Qe(ctx, c.x, c.y, 6, 7.0 + (ctx.phase % 2) * 1.5, ctx.phase * Math.PI / 6);
        const a = ctx.phase * Math.PI * 0.5;
        te(ctx, c.x + Math.cos(a) * 5.2, c.y + Math.sin(a) * 2.5, 1);
      })
    ]
  }, "expansion/weapon/astral_codex");

  // =========================================================================
  // PART B: 14 NEW WEARABLE ARMORS (slot: "top", id: top_<snake_case>)
  // =========================================================================

  // 1. 旅人布袍 (travelerCloak, Common)
  Me({
    id: "top_traveler_cloak", name: "旅人布袍", slot: "top", gameItem: "travelerCloak",
    palettes: { main: P.cream, cloak: P.olive, trim: P.bronze, belt: P.leather },
    parts: [{
      layer: "top",
      draw: ctx => {
        const { g, pose } = ctx, ny = pose.neckY;
        ctx.pal("main");
        J(ctx, rt, { flare: 1.8 }, (s, nx, p) => {
          if (p < 2.2) return 0;
          if (p < 6.4) { ctx.pal("cloak"); return g.t(s, p > 5.7 ? -0.35 : 0.08); }
          ctx.pal("main");
          return g.t(s, 0.04);
        });
        uo(ctx, 8.6, 10.6, "belt", "trim");
        if (pose.cos > 0.3) {
          ctx.pal("trim"); g.clip = true;
          g.ellipse(gt(ctx), ny + 3.6, 1.3, 1.3, s => s > 0 ? 4 : 2);
          g.clip = false;
        }
      }
    }, ...Mt({ key: "cloak", cuffKey: "main", r: 2.0 })]
  }, "expansion/top/traveler_cloak");

  // 2. 铆钉轻甲 (studdedVest, Common)
  Me({
    id: "top_studded_vest", name: "铆钉轻甲", slot: "top", gameItem: "studdedVest",
    palettes: { main: P.leather, strap: P.wood, metal: P.gold, cloth: P.cream },
    parts: [{
      layer: "top",
      draw: ctx => {
        const { g, pose } = ctx, ny = pose.neckY, hw = pose.torsoHalf;
        ctx.pal("main");
        J(ctx, rt, { flare: 2.0 }, (s, nx, p) => p < 2.4 ? 0 : g.t(s, p > 8.6 && p < 9.6 ? -0.4 : 0.05));
        g.clip = true;
        if (pose.cos > 0.2) {
          const cx = gt(ctx);
          ctx.pal("metal");
          for (const py of [4.2, 6.6, 9.0]) {
            g.dot(cx - 2.3, ny + py, 4);
            g.dot(cx + 2.3, ny + py, 3);
          }
        }
        uo(ctx, 9.2, 11.2, "strap", "metal");
        g.clip = false;
      }
    }, ...Mt({ key: "cloth", cuffKey: "strap", r: 1.9 }), ...ae({ key: "main", trimKey: "metal", r: 2.7 })]
  }, "expansion/top/studded_vest");

  // 3. 精钢锁子甲 (chainmailCoat, Rare)
  Me({
    id: "top_chainmail_coat", name: "精钢锁子甲", slot: "top", gameItem: "chainmailCoat",
    palettes: { main: P.blue, mail: P.silver, trim: P.gold },
    parts: [{
      layer: "top",
      draw: ctx => {
        const { g, pose } = ctx, ny = pose.neckY;
        ctx.pal("main");
        J(ctx, rt + 0.5, { flare: 2.4 }, (s, nx, p, x, y) => {
          if (p < 2.4) return 0;
          if (p > rt - 1.6) { ctx.pal("trim"); return ct(ctx, s, 0.15); }
          if (Math.abs(nx) > 0.78) { ctx.pal("mail"); return ((Math.floor(x) + Math.floor(y)) % 2 === 0) ? 3 : 1; }
          ctx.pal("main"); return g.t(s, 0.04);
        });
        if (pose.cos > 0.3) {
          const cx = gt(ctx);
          ctx.pal("trim"); g.clip = true;
          g.line(cx, ny + 3.4, cx, ny + 8.6, 4);
          g.line(cx - 2.3, ny + 5.6, cx + 2.3, ny + 5.6, 3);
          g.clip = false;
        }
        uo(ctx, 9.4, 11.0, "mail", "trim");
      }
    }, ...Mt({ key: "mail", cuffKey: "trim", r: 2.1 }), ...ae({ key: "mail", trimKey: "trim", r: 3.1 })]
  }, "expansion/top/chainmail_coat");

  // 4. 疾风游侠服 (windrunnerGarb, Rare)
  Me({
    id: "top_windrunner_garb", name: "疾风游侠服", slot: "top", gameItem: "windrunnerGarb",
    palettes: { main: P.teal, trim: P.white, leather: P.leather, cloth: P.teal },
    parts: [
      makeArmorCape({ mainKey: "trim", trimKey: "main", lenOffset: 10.5, extraWidth: 2.2, asymmetric: true }),
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx, ny = pose.neckY;
          ctx.pal("main");
          J(ctx, rt, { flare: 2.1 }, (s, nx, p) => {
            if (p < 2.3) return 0;
            if (p < 3.8) { ctx.pal("trim"); return g.t(s, 0.15); }
            ctx.pal("main"); return g.t(s, 0.05);
          });
          uo(ctx, 8.8, 10.6, "leather", "trim");
        }
      },
      ...Mt({ key: "main", cuffKey: "leather", r: 1.95 }),
      ...ae({ key: "leather", trimKey: "trim", r: 2.6, only: "L" })
    ]
  }, "expansion/top/windrunner_garb");

  // 5. 秘银板甲 (mithrilPlate, Epic, + bakeFx shimmer!)
  Me({
    id: "top_mithril_plate", name: "秘银板甲", slot: "top", gameItem: "mithrilPlate",
    palettes: { main: P.silver, trim: P.purple, cloth: P.indigo, fx: P.fxPurp },
    parts: [
      makeArmorCape({ mainKey: "cloth", trimKey: "trim", lenOffset: 7.5, extraWidth: 3.2 }),
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx, ny = pose.neckY;
          ctx.pal("main");
          J(ctx, rt + 0.2, { flare: 2.6 }, (s, nx, p) => {
            if (p < 2.4) return 0;
            if (p > rt - 1.6 || (p > 8.6 && p < 9.5)) { ctx.pal("trim"); return ct(ctx, s, 0.15); }
            ctx.pal("main"); return ct(ctx, s, p < 3.5 ? -0.35 : 0.1);
          });
          if (pose.cos > 0.3) {
            const cx = gt(ctx);
            ctx.pal("trim"); g.clip = true;
            g.ellipse(cx, ny + 5.6, 1.8, 2.0, s => s > 0.2 ? 4 : 2);
            g.clip = false;
          }
        }
      },
      ...Mt({ key: "main", cuffKey: "trim", r: 2.1 }),
      ...ae({ key: "main", trimKey: "trim", r: 3.5, spikes: true }),
      makeArmorGlow("fx", "shoulders")
    ]
  }, "expansion/top/mithril_plate");

  // 6. 奥术星纹袍 (arcaneMantle, Epic, + bakeFx orbiting stars!)
  Me({
    id: "top_arcane_mantle", name: "奥术星纹袍", slot: "top", gameItem: "arcaneMantle",
    palettes: { main: P.indigo, trim: P.gold, cloth: P.purple, fx: P.fxGold },
    parts: [
      makeArmorCape({ mainKey: "cloth", trimKey: "trim", lenOffset: 6.0, extraWidth: 3.6, starry: true }),
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx, ny = pose.neckY;
          ctx.pal("main");
          J(ctx, rt + 1.8, { flare: 3.2 }, (s, nx, p) => {
            if (p < 2.0) return 0;
            if (p > rt + 0.3 || Math.abs(nx) > 0.86 && p > 9.5) { ctx.pal("trim"); return g.t(s, 0.2); }
            ctx.pal("main"); return g.t(s, 0.04);
          });
          if (pose.cos > 0.3) {
            const cx = gt(ctx);
            ctx.pal("trim"); g.clip = true;
            g.line(cx, ny + 3.2, cx, ny + 8.0, 4);
            g.line(cx - 2.2, ny + 5.4, cx + 2.2, ny + 5.4, 4);
            g.clip = false;
          }
          uo(ctx, 8.8, 10.6, "cloth", "trim");
        }
      },
      ...Mt({ key: "main", cuffKey: "trim", r: 2.2, length: 0.82 }),
      ...ae({ key: "cloth", trimKey: "trim", r: 3.0 }),
      makeArmorGlow("fx", "stars")
    ]
  }, "expansion/top/arcane_mantle");

  // 7. 泰坦重堡铠 (titanFortressArmor, Legendary, + bakeFx solar!)
  Me({
    id: "top_titan_fortress_armor", name: "泰坦重堡铠", slot: "top", gameItem: "titanFortressArmor",
    palettes: { main: P.white, trim: P.gold, cloth: P.bronze, gem: P.fire, fx: P.fxGold },
    parts: [{
      layer: "top",
      draw: ctx => {
        const { g, pose } = ctx, ny = pose.neckY;
        ctx.pal("main");
        J(ctx, rt + 0.4, { flare: 3.0, pad: 0.5 }, (s, nx, p) => {
          if (p < 2.4) return 0;
          if (p > rt - 1.8 || (p > 8.2 && p < 9.4)) { ctx.pal("trim"); return ct(ctx, s, 0.2); }
          ctx.pal("main"); return ct(ctx, s, p < 3.6 ? -0.35 : 0.12);
        });
        if (pose.cos > 0.3) {
          const cx = gt(ctx);
          ctx.pal("gem"); g.clip = true;
          g.ellipse(cx, ny + 5.4, 2.2, 2.2, s => s > 0.2 ? 4 : 2);
          g.clip = false;
        }
      }
    }, ...Mt({ key: "cloth", cuffKey: "trim", r: 2.25 }),
      ...ae({ key: "trim", trimKey: "main", r: 4.0, spikes: true }),
      makeArmorGlow("fx", "holy")
    ]
  }, "expansion/top/titan_fortress_armor");

  // 8. 炽凰羽衣 (phoenixFeatherRobe, Legendary, + bakeFx flames!)
  Me({
    id: "top_phoenix_feather_robe", name: "炽凰羽衣", slot: "top", gameItem: "phoenixFeatherRobe",
    palettes: { main: P.crimson, trim: P.gold, cloth: P.fire, fx: P.fxFire },
    parts: [
      makeArmorCape({ mainKey: "cloth", trimKey: "trim", lenOffset: 6.0, extraWidth: 3.8 }),
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx, ny = pose.neckY;
          ctx.pal("main");
          J(ctx, rt + 1.4, { flare: 3.0 }, (s, nx, p) => {
            if (p < 2.2) return 0;
            if (p > rt - 0.5) { ctx.pal("trim"); return ct(ctx, s, 0.25); }
            if (p > 9.5) { ctx.pal("cloth"); return g.t(s, 0.15); }
            ctx.pal("main"); return g.t(s, 0.08);
          });
          if (pose.cos > 0.3) {
            const cx = gt(ctx);
            ctx.pal("trim"); g.clip = true;
            g.tri({ x: cx - 2.2, y: ny + 4.0 }, { x: cx + 2.2, y: ny + 4.0 }, { x: cx, y: ny + 7.8 }, 4);
            g.clip = false;
          }
          uo(ctx, 8.8, 10.6, "trim", "cloth");
        }
      },
      ...Mt({ key: "main", cuffKey: "trim", r: 2.15 }),
      ...ae({ key: "cloth", trimKey: "trim", r: 3.6, spikes: true }),
      makeArmorGlow("fx", "flame")
    ]
  }, "expansion/top/phoenix_feather_robe");

  // 9. 林野叶甲 (wildwoodArmor, Common, Set 1)
  Me({
    id: "top_wildwood_armor", name: "林野叶甲", slot: "top", gameItem: "wildwoodArmor",
    palettes: { main: P.leather, leaf: P.leaf, belt: P.wood, trim: P.woodL },
    parts: [{
      layer: "top",
      draw: ctx => {
        const { g } = ctx;
        ctx.pal("main");
        J(ctx, rt, { flare: 2.2 }, (s, nx, p) => {
          if (p < 2.2) return 0;
          if (p < 5.6 + Math.abs(Math.sin(nx * 6)) * 1.1) { ctx.pal("leaf"); return g.t(s, 0.1); }
          ctx.pal("main"); return g.t(s, 0.02);
        });
        uo(ctx, 9.0, 10.8, "belt", "trim");
      }
    }, ...Mt({ key: "trim", cuffKey: "leaf", r: 2.0 }), ...ae({ key: "leaf", trimKey: "main", r: 3.0 })]
  }, "expansion/top/wildwood_armor");

  // 10. 疾风轻甲 (galeArmor, Rare, Set 2)
  Me({
    id: "top_gale_armor", name: "疾风轻甲", slot: "top", gameItem: "galeArmor",
    palettes: { main: P.blue, trim: P.white, cloth: P.teal, metal: P.silver },
    parts: [
      makeArmorCape({ mainKey: "trim", trimKey: "cloth", lenOffset: 8.5, extraWidth: 3.0, asymmetric: true }),
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx, ny = pose.neckY;
          ctx.pal("main");
          J(ctx, rt, { flare: 2.3 }, (s, nx, p) => {
            if (p < 2.3) return 0;
            if (p > rt - 1.5) { ctx.pal("trim"); return g.t(s, 0.2); }
            ctx.pal("main"); return ct(ctx, s, 0.06);
          });
          if (pose.cos > 0.3) {
            const cx = gt(ctx);
            ctx.pal("trim"); g.clip = true;
            g.line(cx - 2.4, ny + 4.4, cx + 2.4, ny + 6.4, 4);
            g.clip = false;
          }
          uo(ctx, 9.0, 10.6, "metal", "trim");
        }
      },
      ...Mt({ key: "cloth", cuffKey: "trim", r: 2.0 }),
      ...ae({ key: "trim", trimKey: "main", r: 3.1 })
    ]
  }, "expansion/top/gale_armor");

  // 11. 橡木重甲 (oakArmor, Rare, Set 3)
  Me({
    id: "top_oak_armor", name: "橡木重甲", slot: "top", gameItem: "oakArmor",
    palettes: { main: P.bronze, bark: P.wood, moss: P.leaf, trim: P.woodL },
    parts: [{
      layer: "top",
      draw: ctx => {
        const { g, pose } = ctx, ny = pose.neckY;
        ctx.pal("main");
        J(ctx, rt + 0.3, { flare: 2.6, pad: 0.3 }, (s, nx, p, x, y) => {
          if (p < 2.4) return 0;
          if (p > rt - 1.6) { ctx.pal("trim"); return ct(ctx, s, 0.1); }
          ctx.pal("main");
          const grain = Math.sin(x * 2.1 + y * 0.4) > 0.65 ? -0.35 : 0.08;
          return ct(ctx, s, grain);
        });
        if (pose.cos > 0.3) {
          const cx = gt(ctx);
          ctx.pal("moss"); g.clip = true;
          g.ellipse(cx, ny + 5.6, 1.9, 1.9, s => s > 0.1 ? 4 : 2);
          g.clip = false;
        }
        uo(ctx, 9.2, 11.0, "bark", "trim");
      }
    }, ...Mt({ key: "bark", cuffKey: "main", r: 2.15 }), ...ae({ key: "main", trimKey: "moss", r: 3.5 })]
  }, "expansion/top/oak_armor");

  // 12. 秘焰法袍 (emberArmor, Epic, Set 5, + bakeFx flame!)
  Me({
    id: "top_ember_armor", name: "秘焰法袍", slot: "top", gameItem: "emberArmor",
    palettes: { main: P.purple, flame: P.fire, cloth: P.crimson, trim: P.gold, fx: P.fxFire },
    parts: [
      makeArmorCape({ mainKey: "cloth", trimKey: "flame", lenOffset: 6.8, extraWidth: 3.4 }),
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx, ny = pose.neckY;
          ctx.pal("main");
          J(ctx, rt + 1.4, { flare: 3.0 }, (s, nx, p) => {
            if (p < 2.2) return 0;
            if (p > rt - 1.2) { ctx.pal("flame"); return g.t(s, 0.25); }
            ctx.pal("main"); return g.t(s, 0.05);
          });
          if (pose.cos > 0.3) {
            const cx = gt(ctx);
            ctx.pal("flame"); g.clip = true;
            g.tri({ x: cx - 2.0, y: ny + 6.6 }, { x: cx + 2.0, y: ny + 6.6 }, { x: cx, y: ny + 3.2 }, 4);
            g.clip = false;
          }
          uo(ctx, 8.8, 10.6, "trim", "flame");
        }
      },
      ...Mt({ key: "main", cuffKey: "flame", r: 2.1 }),
      ...ae({ key: "main", trimKey: "flame", r: 3.4, spikes: true }),
      makeArmorGlow("fx", "flame")
    ]
  }, "expansion/top/ember_armor");

  // 13. 苍穹光铠 (aegisArmor, Legendary, Set 7, + bakeFx seraph!)
  Me({
    id: "top_aegis_armor", name: "苍穹光铠", slot: "top", gameItem: "aegisArmor",
    palettes: { main: P.white, trim: P.gold, cloth: P.white, fx: P.fxGold },
    parts: [
      makeArmorCape({ mainKey: "cloth", trimKey: "trim", lenOffset: 6.2, extraWidth: 3.8 }),
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx, ny = pose.neckY;
          ctx.pal("main");
          J(ctx, rt + 0.4, { flare: 2.8, pad: 0.3 }, (s, nx, p) => {
            if (p < 2.4) return 0;
            if (p > rt - 1.7 || Math.abs(Math.abs(nx) - 0.94) < 0.05) { ctx.pal("trim"); return ct(ctx, s, 0.2); }
            ctx.pal("main"); return ct(ctx, s, 0.14);
          });
          if (pose.cos > 0.3) {
            const cx = gt(ctx);
            ctx.pal("trim"); g.clip = true;
            g.line(cx, ny + 3.0, cx, ny + 8.6, 4);
            g.line(cx - 2.6, ny + 5.2, cx + 2.6, ny + 5.2, 4);
            g.clip = false;
          }
          uo(ctx, 9.2, 10.8, "trim", "main");
        }
      },
      ...Mt({ key: "main", cuffKey: "trim", r: 2.2 }),
      ...ae({ key: "main", trimKey: "trim", r: 3.8, spikes: true }),
      makeArmorGlow("fx", "holy")
    ]
  }, "expansion/top/aegis_armor");

  // 14. 星辰法衣 (astralArmor, Legendary, Set 8, + bakeFx constellation!)
  Me({
    id: "top_astral_armor", name: "星辰法衣", slot: "top", gameItem: "astralArmor",
    palettes: { main: P.indigo, trim: P.gold, cloth: P.purple, blue: P.blue, fx: P.fxGold },
    parts: [
      makeArmorCape({ mainKey: "cloth", trimKey: "trim", lenOffset: 5.8, extraWidth: 4.0, starry: true }),
      {
        layer: "top",
        draw: ctx => {
          const { g, pose } = ctx, ny = pose.neckY;
          ctx.pal("main");
          J(ctx, rt + 1.8, { flare: 3.4 }, (s, nx, p, x, y) => {
            if (p < 2.0) return 0;
            if (p > rt + 0.3) { ctx.pal("trim"); return ct(ctx, s, 0.25); }
            if (((Math.floor(x * 1.5) * 13 + Math.floor(y * 1.5) * 29) % 23 === 0) && p > 4.0) {
              ctx.pal("trim"); return 4;
            }
            ctx.pal("main"); return g.t(s, 0.05);
          });
          if (pose.cos > 0.3) {
            const cx = gt(ctx);
            ctx.pal("trim"); g.clip = true;
            g.line(cx - 2.4, ny + 4.0, cx, ny + 6.4, 3);
            g.line(cx, ny + 6.4, cx + 2.5, ny + 4.4, 3);
            g.dot(cx - 2.4, ny + 4.0, 4); g.dot(cx, ny + 6.4, 4); g.dot(cx + 2.5, ny + 4.4, 4);
            g.clip = false;
          }
          uo(ctx, 8.8, 10.6, "blue", "trim");
        }
      },
      ...Mt({ key: "blue", cuffKey: "trim", r: 2.2, length: 0.82 }),
      ...ae({ key: "main", trimKey: "trim", r: 3.4, spikes: true }),
      makeArmorGlow("fx", "stars")
    ]
  }, "expansion/top/astral_armor");
}

registerEquipmentExpansion({k,v,Me,J,gt,Mt,Pe,ae,uo,ue,ut,wt,z,Q,V,_t,Et,pt,ct,St,Z,lt,O,ye,jt,At,ko,Ut,xe,te,be,Qe,rt});
// --- END PROCEDURAL EQUIPMENT EXPANSION ---
function h0(o){return ie.get(o)}function f0(o){const t=o==="weapon_off"?["weapon_off","weapon_main"]:[o];return[...ie.values()].filter(e=>t.includes(e.slot))}function Io(o){var e;const t=new sa(ha);o.skin&&we[o.skin]&&t.setBodyPalette(we[o.skin]);for(const a of Ke){const n=o.slots[a];if(!n)continue;const r=h0(n);if(!r)throw new Error(`unknown item ${n}`);t.equip(a,r)}for(const[a,n]of Object.entries((e=o.variants)!=null?e:{}))n&&t.setVariant(a,n);return t}function d0(o){var f,h;const t=JSON.parse(o),e=Io(t).resolve(),a=(f=t.dirs)!=null?f:Nt,n=(h=t.frames)!=null?h:Array.from({length:Ot},(d,w)=>w),r=G*n.length,i=Y*a.length,s=new Uint8Array(r*i*4),l=new Uint8ClampedArray(G*Y*4),c=new qt(G,Y);return a.forEach((d,w)=>{n.forEach((p,u)=>{c.clear(),me(e,d,p,c),c.toRGBA(l);for(let m=0;m<Y;m++)s.set(l.subarray(m*G*4,(m+1)*G*4),((w*Y+m)*r+u*G)*4)})}),s}function p0(){const o=t=>f0(t).map(e=>{var a;return{id:e.id,name:e.name,gameItem:e.gameItem,hold:e.hold,attack:e.attack,variants:((a=e.variants)!=null?a:[]).map(n=>({id:n.id,name:n.name}))}});return JSON.stringify({sprW:G,sprH:Y,scale:$,framesPerDir:Ot,impact:Do,dirs:Nt,footPx:[pt*$,Et*$],frames:{idle:vo,walk:Go,walk8:Xo,ready:Ko,...Po,...Uo},items:Object.fromEntries(["hair","face","top","bottom","shoes","scarf","bag","weapon_main"].map(t=>[t,o(t)])),skins:Object.keys(we)})}function m0(o){const t=o||void 0,e=$;return JSON.stringify(Nt.map(a=>Array.from({length:Ot},(n,r)=>vt(a,r,{armedR:t}).legs.map(s=>[+(s.foot.x*e).toFixed(2),+(s.foot.y*e).toFixed(2)]))))}function u0(o,t,e){const a=o||void 0,n=$;return JSON.stringify(JSON.parse(e).map(r=>vt(t,r,{armedR:a}).legs.map(i=>[+(i.foot.x*n).toFixed(2),+(i.foot.y*n).toFixed(2)])))}function w0(o,t,e){const a=o||void 0,n=vt(t,e,{armedR:a}),r=a==="bow"?n.handL:n.handR,i=$;return JSON.stringify([r.x*i,r.y*i,r.angle,r.reach,i])}function g0(o){const t=o||void 0,e=$;return JSON.stringify(Nt.map(a=>Array.from({length:Ot},(n,r)=>{const i=vt(a,r,{armedR:t}),s=t==="bow"?i.handL:i.handR;return[+(s.x*e).toFixed(2),+(s.y*e).toFixed(2),+s.angle.toFixed(3),+s.reach.toFixed(3)]})))}function y0(o){var d,w;const t=JSON.parse(o),e=Io(t).resolve();if(!e.some(p=>p.item.parts.some(u=>u.glow)))return new Uint8Array(0);const a=(d=t.dirs)!=null?d:Nt,n=(w=t.frames)!=null?w:Array.from({length:Ot},(p,u)=>u),r=4,i=G*n.length,s=Y*a.length*r,l=new Uint8Array(i*s*4),c=new Uint8ClampedArray(G*Y*4),f=new Uint8ClampedArray(G*Y*4),h=new qt(G,Y);return a.forEach((p,u)=>{n.forEach((m,y)=>{h.clear(),me(e,p,m,h,{glow:!1}),h.toRGBA(c);for(let g=0;g<r;g++){h.clear(),me(e,p,m,h,{phase:g}),h.toRGBA(f);for(let _=0;_<Y;_++)for(let x=0;x<G;x++){const b=(_*G+x)*4;f[b+3]!==0&&(f[b]===c[b]&&f[b+1]===c[b+1]&&f[b+2]===c[b+2]&&f[b+3]===c[b+3]||l.set(f.subarray(b,b+4),(((u*r+g)*Y+_)*i+y*G+x)*4))}}})}),l}globalThis.PixelBaker={info:p0,bake:d0,bakeFx:y0,feet:m0,hands:g0,feetAt:u0,handAt:w0}})();
