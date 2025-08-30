FROM nginx:alpine

# Copy static files into Nginx document root
COPY . /usr/share/nginx/html

# Expose port 80
EXPOSE 80

# Use default nginx entrypoint
CMD ["nginx", "-g", "daemon off;"]