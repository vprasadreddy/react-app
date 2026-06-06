FROM node:alpine AS build
ARG REACT_APP_ENVIRONMENT
ENV REACT_APP_ENVIRONMENT=${REACT_APP_ENVIRONMENT}
WORKDIR /app
COPY package.json /app/package.json
RUN npm i
COPY . /app/
EXPOSE 3000
RUN npm run build
CMD ["npm", "start"]