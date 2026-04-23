# VSP — JavaScript / TypeScript / Node Vulnerability Taxonomy

Focus on these bug classes (ordered by frequency in real JS CVEs):

## 1. Prototype Pollution
- `Object.assign({}, ...user)`, `_.merge(target, user)`, `_.defaultsDeep`, `jQuery.extend(true, ...)`
- Manual recursive merge: `for (k in src) dst[k] = src[k]` where `k` could be `__proto__` / `constructor` / `prototype`
- `JSON.parse` followed by merge into a config object
- Consequences: auth bypass (setting `.isAdmin = true` on prototype), RCE via gadget (`.shell`, `.argv0`, `.NODE_OPTIONS` depending on loaded libs)
- Check whether `Object.create(null)` or `Map` is used instead

## 2. Code Injection
- `eval(user_string)`, `new Function(user_string)`, `setTimeout(user_string, ...)`, `setInterval(user_string, ...)`
- `vm.runInContext`, `vm.runInNewContext`, `vm.runInThisContext` (`vm` is NOT a sandbox)
- Template engines: Handlebars `{{{raw}}}`, EJS with user templates, Pug `!=`, `serialize-javascript` + `unsafe:true`
- React: `dangerouslySetInnerHTML={{__html: user}}`
- Angular: `[innerHTML]=user`, `bypassSecurityTrustHtml`

## 3. Command Injection
- `child_process.exec(user)`, `child_process.execSync`, `spawn(..., {shell:true})`
- Even `execFile` can be injected via `--option=...` (argument injection) if user controls any arg
- `shelljs.exec`, `zx` template literals

## 4. Path Traversal / Arbitrary File Read
- `fs.readFile(user)`, `fs.createReadStream(user)`, `res.sendFile(user)`, `res.download(user)`
- `path.join(safe, user)` does NOT prevent `..` — use `path.resolve` + prefix check
- Express `res.sendFile` requires `{root: ...}` option; without it, absolute paths read anywhere
- Archive extraction: `tar`, `adm-zip`, `decompress` → zip-slip

## 5. SSRF
- `fetch(user_url)`, `axios.get(user_url)`, `request(user_url)`, `http.get(user_url)`
- No private-IP block, no scheme allow-list
- Check for DNS rebinding window if the URL is fetched twice (validate → fetch)
- Next.js image optimizer, GraphQL federation, OAuth callback URLs

## 6. XSS
- `innerHTML =`, `outerHTML =`, `document.write`, `insertAdjacentHTML`
- `$.html()`, `$(selector).html(user)` (jQuery)
- React: `dangerouslySetInnerHTML`, user-controlled `href=javascript:...`, unsanitized SVG
- Express templates with raw output blocks
- JSON embedded in HTML: `<script>var x = ${JSON.stringify(user)}</script>` — `</script>` in user string breaks out

## 7. SQL / NoSQL Injection
- Template literals in queries: `db.query(\`SELECT ... WHERE id=${user}\`)` — NOT parameterized
- Mongoose `$where: user_string`, `find(user_object)` where user controls operator keys (`$ne`, `$gt`)
- Raw SQLAlchemy-style APIs in knex/sequelize: `whereRaw(user)`, `rawQuery`

## 8. ReDoS
- User-controlled input matched against a regex with catastrophic backtracking: `(a+)+$`, `(a|a)+`, nested quantifiers on repeating groups
- User-controlled **regex pattern** passed to `new RegExp(user)` → author any ReDoS
- Any regex in a hot path (auth, validation) reachable with attacker-controlled input

## 9. Open Redirect & Header Injection
- `res.redirect(user_url)` without scheme/host check
- `res.setHeader('Location', user)`, `res.setHeader('Set-Cookie', user)` — CR/LF injection in older Node
- `window.location = user` in SPA router after pushState

## 10. Authentication / JWT / Crypto
- `jwt.verify(token, secret, {algorithms: ['none']})` — or missing `algorithms` opt → alg confusion attack
- `jsonwebtoken` version <8 key-confusion
- `crypto.randomBytes` vs `Math.random` for tokens
- `===` vs `crypto.timingSafeEqual` on session tokens

## Node/TS-specific VSP reasoning

1. **Input enumeration:** Express `req.body`, `req.query`, `req.params`, `req.headers`, `req.cookies`, `req.files` (multer), WebSocket `.on('message')`, IPC channels, `process.env` for exposed services
2. **TypeScript types are compile-time only.** `req.body: UserDTO` does not enforce; at runtime the object can have any keys including `__proto__`. Only runtime validators (Zod, io-ts, class-validator) help.
3. **Monorepo / nested `node_modules`:** a pollution gadget reachable in one package can affect another package that does not even import it, because they share `Object.prototype` in one VM.
4. **`vm` is not a sandbox.** Use `vm2` (known-broken historically), `isolated-vm`, or process isolation.
5. **Lodash / common gadgets:** versions before 4.17.21 have prototype-pollution CVEs; check `package.json`.
6. **ESM vs CommonJS:** dynamic `import(user)` runs the module's top-level code.
