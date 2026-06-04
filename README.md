# Quanto eu tenho que me foder

🔗 **https://quantoeutenhoquemefoder.com.br**

PWA mobile-first que lê o preço de uma etiqueta pela câmera (OCR **100% local**, via
[Tesseract.js](https://tesseract.projectnaptha.com/)) e mostra **quanto tempo de trabalho**
aquele produto custa, sobreposto na tela em cima de uma mira.

> Nenhuma imagem sai do aparelho. Todo o reconhecimento roda no dispositivo.

## Como funciona

1. Na primeira vez, escolha o **valor base**: **seu salário** mensal líquido **ou** o
   **salário mínimo de um país** (Brasil + 20 maiores economias, com bandeira). No modo país,
   o mínimo local é convertido para R$ pela cotação atual — então, se você "ganhasse em dólar",
   vê quanto tempo trabalharia por um produto **precificado em real** (evidenciando a diferença).
   Também dá para ajustar as horas/mês (padrão CLT = 220).
2. Aponte a câmera traseira para a etiqueta, alinhando o preço dentro da **mira**.
3. O app recorta **apenas a região da mira (ROI)** e roda OCR só nela, com *throttle*.
4. Mostra o resultado **na primeira leitura** (sem espera). Se houver **vários preços
   empilhados** (um embaixo do outro), lê todos e exibe **um tempo por linha**, alinhado
   à posição real de cada preço.
5. Cada linha mostra o **tempo de trabalho** (`4h 12min`, `2d 3h`, `45s`...) + o preço,
   num bloco com as **cores amostradas daquela linha da etiqueta** (contraste WCAG ≥ 4.5:1).
6. O resultado fica nítido por ~4,5 s e esmaece (~6 s no total); o OCR retoma no início do
   *fade*. Tudo é calibrável no objeto **`CONFIG`** no topo do `<script>` em `index.html`.
7. Botões discretos para editar o **valor base** e ver o **histórico** (exportável via
   compartilhamento nativo do celular, com *fallback* para cópia/download `.txt`).

`valor_hora = salario_mensal / HORAS_MES` · `horas = preço / valor_hora`

## Arquivos

| Arquivo | Função |
|---|---|
| `index.html` | App completo e autocontido (HTML + CSS + JS inline). Funciona sozinho. |
| `economias.json` | Brasil + 20 maiores economias: bandeira, nome, moeda, salário mínimo mensal e `cotacaoBRL`. |
| `update-rates.sh` | Atualiza as cotações em `economias.json` via API pública de câmbio. Para o cron. |
| `manifest.json`, `icon.svg`, `sw.js` | Instalabilidade (PWA) + cache offline opcional. |
| `Dockerfile`, `nginx.conf` | Imagem estática servida por nginx. |
| `docker-compose.yml` | Publicação via Traefik (HTTPS/Let's Encrypt) + volume do `economias.json`. |
| `deploy.sh` | Commit + push + deploy no servidor. |

## Cotações de câmbio (cron)

O `economias.json` traz o salário mínimo de cada país em moeda local + um campo `cotacaoBRL`
(quantos reais vale 1 unidade da moeda). O script **`update-rates.sh`** busca o câmbio atual
numa API pública gratuita (`open.er-api.com`, com fallback `frankfurter.app`) e reescreve o JSON.

O `docker-compose.yml` monta o `economias.json` do host como volume — então o cron atualiza o
arquivo e o nginx já serve a versão nova **sem rebuild**.

Agende no cron do servidor (ex.: todo dia às 06:00):

```cron
0 6 * * * /root/quantoeutenhoquemefoder/update-rates.sh >> /var/log/qtqmf-rates.log 2>&1
```

> "Chamável via URL": o script consome a URL da API de câmbio. Se quiser dispará-lo por um
> webhook, basta apontar um job/cron externo (`curl`) para um endpoint que execute este script.

## Deploy

É um app **estático**. Exige **HTTPS** (a API de câmera `getUserMedia` só funciona em
contexto seguro). Basta servir os arquivos e apontar o subdomínio para a pasta.

### Via Docker + Traefik (este repo)

```bash
docker compose up --build -d
```

O `docker-compose.yml` registra no Traefik o host `quantoeutenhoquemefoder.com.br` (+ www),
com redirect HTTP→HTTPS e certificado Let's Encrypt automático. Requer a rede
externa `traefik_net` (já existente no servidor).

### Servidor estático qualquer

Copie `index.html`, `manifest.json`, `icon.svg` e `sw.js` para a raiz pública de um
host com HTTPS. Nada mais é necessário.

## Compatibilidade

Testado mentalmente para **Chrome Android** e **Safari iOS** (`playsinline`, gesto do
usuário para iniciar a câmera, `facingMode: environment`). Degrada com mensagens
claras se a câmera ou o OCR falharem.
