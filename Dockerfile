# App estático (HTML + JS inline). Sem build — apenas servir via nginx.
FROM nginx:alpine

# Configuração do servidor
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Arquivos estáticos do PWA (economias.json é a versão inicial; o cron atualiza via volume)
COPY index.html manifest.json sw.js economias.json \
     icon.svg icon-192.png icon-512.png apple-touch-icon.png favicon-16.png favicon-32.png \
     og-image.png og-image.svg \
     robots.txt sitemap.xml \
     /usr/share/nginx/html/

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
