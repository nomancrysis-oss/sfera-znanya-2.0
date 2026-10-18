'use strict';
// These TWO values are public. A secret/service-role key must never be returned.
module.exports = function config(request, response) {
  response.setHeader('Cache-Control','no-store');
  response.setHeader('X-Content-Type-Options','nosniff');
  if(request.method!=='GET')return response.status(405).json({error:'Method not allowed'});
  const url=(process.env.SUPABASE_URL||'').trim().replace(/\/$/,'');
  const key=(process.env.SUPABASE_PUBLISHABLE_KEY||'').trim();
  if(!/^https:\/\/[a-z0-9-]+\.supabase\.co$/.test(url)||!/^sb_publishable_[A-Za-z0-9_-]+$/.test(key)){
    return response.status(503).json({error:'Подключение не настроено: добавьте SUPABASE_URL и SUPABASE_PUBLISHABLE_KEY в Vercel → Settings → Environment Variables, затем выполните Redeploy.'});
  }
  return response.status(200).json({url,key});
};
