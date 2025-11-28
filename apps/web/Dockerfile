FROM nginx:1.25-alpine
RUN rm -rf /usr/share/nginx/html/*
# Superapp (Endkunden-Frontend) unter /
COPY clients/shamell_flutter/build/web/ /usr/share/nginx/html/

# Ops-Admin-Frontend unter /ops-admin/
COPY clients/ops_admin_flutter/build/web/ /usr/share/nginx/html/ops-admin/

COPY apps/web/nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 8080
CMD ["nginx","-g","daemon off;"]
