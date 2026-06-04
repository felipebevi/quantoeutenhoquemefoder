# App estático (HTML + JS inline). Sem build — apenas servir via nginx.
FROM nginx:alpine

# Configuração do servidor
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Arquivos estáticos do PWA (economias.json é a versão inicial; o cron atualiza via volume)
COPY index.html manifest.json icon.svg icon-192.png icon-512.png apple-touch-icon.png sw.js economias.json /usr/share/nginx/html/

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
