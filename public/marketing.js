// Outfit photos stay within the authenticated workspace; no public image host.
export async function outfitPhoto(file){
 if(!file?.size)return null;
 if(!['image/jpeg','image/png','image/webp'].includes(file.type))throw Error('Choose a JPG, PNG or WebP outfit photo.');
 if(file.size>12*1024*1024)throw Error('Choose a photo smaller than 12 MB.');
 const bitmap=await createImageBitmap(file);try{const scale=Math.min(1,480/Math.max(bitmap.width,bitmap.height)),canvas=document.createElement('canvas');canvas.width=Math.max(1,Math.round(bitmap.width*scale));canvas.height=Math.max(1,Math.round(bitmap.height*scale));const ctx=canvas.getContext('2d');ctx.fillStyle='#f6efe6';ctx.fillRect(0,0,canvas.width,canvas.height);ctx.drawImage(bitmap,0,0,canvas.width,canvas.height);const image=canvas.toDataURL('image/jpeg',.75);if(image.length>300000)throw Error('This photo is too detailed. Try a smaller photo.');return image;}finally{bitmap.close();}
}
export function marketingOverview(rows){return {total:rows.length,sent:rows.filter(r=>r.status==='Sent').length,completed:rows.filter(r=>['Posted','Returned'].includes(r.status)).length};}
export function marketingMatches(row,query){return [row.influencer_name,row.outfit_name,row.agency_name,row.sent_through,row.collaboration,row.status].some(v=>String(v||'').toLowerCase().includes(query.toLowerCase()));}
