import { defineRouteMiddleware } from '@astrojs/starlight/route-data';

// src/content/docs is a link to docs/: "Edit page" should open the real file.
export const onRequest = defineRouteMiddleware((context) => {
  const route = context.locals.starlightRoute;
  if (route.editUrl) {
    route.editUrl = new URL(route.editUrl.href.replace('/edit/main/src/content/docs/', '/edit/main/docs/'));
  }
});
