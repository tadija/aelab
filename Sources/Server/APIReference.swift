/// Small authenticated OpenAPI viewer; the palette is shared with the dashboard's static assets.
enum APIReference {
    static func html(base: String) -> String {
        document.replacingOccurrences(of: "href=\"/", with: "href=\"" + base + "/")
            .replacingOccurrences(of: "fetch('/api/", with: "fetch('" + base + "/api/")
    }
    private static let document = #"""
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>aelab API</title>
      <link rel="stylesheet" href="/theme.css">
      <style>
        *{box-sizing:border-box}body{margin:0;font-size:16px;line-height:1.5}
        main{max-width:960px;margin:auto;padding:48px 24px 64px}
        header{display:flex;align-items:center;justify-content:space-between;gap:16px}
        h1{display:flex;align-items:center;gap:12px;font-size:2rem;margin:0}
        h1 a{display:inline-flex;align-items:center;gap:10px;color:var(--text)}h1 span{color:var(--muted);font-size:1rem;font-weight:500}
        a{color:var(--accent);text-decoration:none;font-weight:600}a:hover{text-decoration:underline}
        nav{display:flex;flex-wrap:wrap;gap:16px;margin:20px 0}p{color:var(--muted)}
        button{font:inherit;color:var(--text);background:var(--panel);border:1px solid var(--border);border-radius:8px;padding:6px 10px;cursor:pointer}
        button:hover{background:var(--control);color:var(--accent)}button:focus-visible,a:focus-visible,summary:focus-visible{outline:2px solid var(--accent);outline-offset:3px}
        details{margin:12px 0;border:1px solid var(--border);border-radius:12px;background:var(--panel)}
        summary{cursor:pointer;padding:14px 16px;overflow-wrap:anywhere;font-weight:600}summary::marker{color:var(--muted)}
        .route-group>summary{background:var(--control);border-radius:11px}.route-group[open]>summary{border-radius:11px 11px 0 0}.route-group>div{padding:0 12px}.route-group .route-group>summary{font-size:.9rem}
        .method{display:inline-block;margin-right:8px;padding:2px 7px;border-radius:5px;background:var(--control);color:var(--accent);font:600 12px ui-monospace,SFMono-Regular,Menlo,monospace}
        pre{margin:0 12px 12px;padding:14px;border-radius:8px;background:var(--control);color:var(--text);white-space:pre-wrap;overflow-wrap:anywhere;font:13px/1.6 ui-monospace,SFMono-Regular,Menlo,monospace}
        .error{color:var(--text);background:var(--control);border:1px solid var(--border);padding:12px;border-radius:8px}
        @media(max-width:600px){main{padding:24px 16px}summary{padding:12px}pre{margin:0 8px 8px;padding:10px}}
      </style>
      <script>
        function readTheme(){try{return localStorage.getItem('aelab-theme:overview')==='light'?'light':'dark'}catch{return 'dark'}}
        document.documentElement.dataset.theme=readTheme();
      </script>
    </head>
    <body><main>
      <header><h1><a href="/" aria-label="aelab dashboard"><svg viewBox="0 0 24 24" width="24" height="24" aria-hidden="true"><circle cx="12" cy="12" r="8.5" fill="none" stroke="currentColor" stroke-width="3"/><circle cx="12" cy="12" r="3" fill="currentColor"/></svg>aelab</a><span>API</span></h1><button id="theme" aria-label="Toggle theme">◐</button></header>
      <nav aria-label="API navigation"><a href="/">Dashboard</a><a href="/api/docs/openapi.json">OpenAPI JSON</a></nav>
      <p id="intro"></p><p id="loading" role="status">Loading API reference…</p><div id="routes"></div>
      <script>
        document.getElementById('theme').addEventListener('click',()=>{
          const theme=document.documentElement.dataset.theme==='dark'?'light':'dark';
          document.documentElement.dataset.theme=theme;
          try{localStorage.setItem('aelab-theme:overview',theme)}catch{}
        });
        (async()=>{
          try{
            const response=await fetch('/api/docs/openapi.json');const doc=await response.json();
            if(!response.ok)throw new Error(doc.error?.message||'Unable to load API reference');
            document.getElementById('intro').textContent=doc.info.description;
            const routes=document.getElementById('routes'),prefix='/api/hosts/{host}';
            function group(label,parent){
              const details=document.createElement('details'),summary=document.createElement('summary'),body=document.createElement('div');
              details.className='route-group';summary.textContent=label;details.append(summary,body);parent.append(details);return body;
            }
            let hostGroups;const sectionGroups=new Map();
            for(const [path,methods] of Object.entries(doc.paths))for(const [method,op] of Object.entries(methods)){
              let parent=routes;
              if(path.startsWith(prefix+'/')){
                if(!hostGroups){
                  const hosts=group(prefix,routes);
                  hostGroups=Object.fromEntries(['Host & discovery','Plugins','Services','Shells'].map(label=>[label,group(label,hosts)]));
                }
                const resource=path.slice(prefix.length+1).split('/')[0];
                parent=hostGroups[resource==='plugins'?'Plugins':resource==='services'?'Services':['terminals','temporary-terminals','terminal-tickets','tmux'].includes(resource)?'Shells':'Host & discovery'];
              }
              const section=['/api/auth','/api/config','/api/state','/api/docs'].find(prefix=>path===prefix||path.startsWith(prefix+'/'));
              if(section){
                if(!sectionGroups.has(section))sectionGroups.set(section,group(section,routes));
                parent=sectionGroups.get(section);
              }
              const details=document.createElement('details'),summary=document.createElement('summary'),badge=document.createElement('span'),pre=document.createElement('pre');
              badge.className='method';badge.textContent=method.toUpperCase();summary.append(badge,document.createTextNode(path));
              pre.textContent=JSON.stringify(op,null,2);details.append(summary,pre);parent.append(details);
            }
          }catch(error){const notice=document.createElement('p');notice.className='error';notice.setAttribute('role','alert');notice.textContent=error instanceof TypeError?'Server is offline':error.message;document.getElementById('routes').append(notice)}
          finally{document.getElementById('loading').remove()}
        })();
      </script>
    </main></body></html>
    """#
}
