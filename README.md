# AI Agents Day — [aiagents.day](https://aiagents.day)

Sitio web del evento virtual **AI Agents Day**, construido con [Hugo](https://gohugo.io)
y el theme [Hugo Event Theme](https://github.com/medialesson/hugo-theme-event)
(basado en [hugo-theme-event-demo](https://github.com/medialesson/hugo-theme-event-demo)).

## Requisitos

- [Hugo extended](https://gohugo.io/installation/) ≥ 0.126
- Git (el theme es un submódulo)

## Desarrollo local

```shell
git clone --recurse-submodules <repo-url>
# o, si ya clonaste sin submódulos:
git submodule update --init --recursive

hugo server
```

Abre http://localhost:1313/ (español) y http://localhost:1313/en/ (inglés).

## Estructura

| Ruta | Descripción |
| --- | --- |
| `hugo.yaml` | Configuración del sitio: textos, fechas, colores, menús, CTA |
| `i18n/es.yaml`, `i18n/en.yaml` | Traducciones de la interfaz del theme |
| `content/` | Páginas propias (código de conducta, privacidad) |
| `content/_content.gotmpl` | Genera las páginas *Acerca de*, *Sponsors* y *Ubicación* con títulos traducidos |
| `assets/logos/` | Logo (placeholder) |
| `static/` | Favicon y `CNAME` (`aiagents.day`) |
| `themes/event/` | Submódulo del theme — no editar directamente |

## Pendientes (`TODO` en `hugo.yaml`)

- [ ] Fecha real del evento (`startDate` / `endDate`)
- [ ] URL de registro (`callToAction.other.url`) o ID de Eventbrite
- [ ] URL del Call for Speakers (`callToActionSecondary.url`)
- [ ] `sessionizeId` — al configurarlo se generan automáticamente la **agenda** y los **speakers**
- [ ] Redes sociales, sponsors y organizadores
- [ ] Logo, favicon e imagen de portada definitivos
- [ ] Contenido de *Acerca de* (`aboutUs`) y política de privacidad

## Despliegue

El workflow [`.github/workflows/hugo.yaml`](.github/workflows/hugo.yaml) publica el sitio en
GitHub Pages en cada push a `main`. En *Settings → Pages* selecciona **GitHub Actions** como
fuente y configura el dominio personalizado `aiagents.day` (apuntando el DNS a GitHub Pages).
