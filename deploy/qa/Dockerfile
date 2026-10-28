# The QA suite for Railway (services: lbm-qa in staging, lbm-qa-live in
# production), ported from the Empower Health suite on 2026-10-22. Railway uses this file via
# RAILWAY_DOCKERFILE_PATH=deploy/qa/Dockerfile, building from the repo root.
#   /        the QA page (deploy/qa/harness): checklist, phone frame, console
#   /app/    the app under test
#   /api/    the shared checklist, notes and bug reports, kept on the Railway
#            volume mounted at /data
#   /img     the app's picture pass-through, as on the web app
#
# Which backend is the Railway variable LBM_ENV, read here as a build arg:
#   dev  (the default, and staging's lbm-qa) the dev Firebase project and the
#        dev Shopify shop. Testers add to carts, post and check out, and none
#        of it reaches real customers (Grace, 2026-10-22).
#   prod (production's lbm-qa-live) the LIVE project and the real shop, so
#        the suite shows exactly what customers see (Grace, 2026-10-28). Here
#        every post, message and order a tester makes is real.
# Anything else fails the build rather than guessing.

# The same Flutter as the website (Dockerfile.web). Pinned to 3.41.6 like
# Empower Health, the web compile failed: firebase_core_web needs a newer
# Dart than that release carries.
FROM ghcr.io/cirruslabs/flutter:stable AS build
ARG RAILWAY_GIT_COMMIT_SHA
ARG RAILWAY_GIT_BRANCH
ARG LBM_ENV=dev
WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get
COPY . .
# That project's Firebase settings, over whichever were last swapped in.
RUN case "$LBM_ENV" in dev|prod) ;; *) echo "LBM_ENV must be dev or prod, got '$LBM_ENV'" >&2; exit 1;; esac && \
    cp "firebase/config/$LBM_ENV/firebase_options.dart" lib/firebase_options.dart && \
    grep -m1 "projectId:" lib/firebase_options.dart
# Map widget classes to source for layout findings (web has no creation
# tracking).
RUN dart run tool/gen_qa_widget_index.dart
# Debug mode keeps Flutter's layout assertions (overflow errors). QA_HARNESS
# turns on the bridge in lib/qa/; LBM_DEV turns on the error strip with Copy
# for Claude, the backend badge and Diagnostics, which a debug build allows.
RUN flutter build web --debug --base-href /app/ \
    --dart-define=QA_HARNESS=true --dart-define=LBM_DEV=true -o /out/app
RUN printf '{"commit":"%s","branch":"%s"}\n' "$RAILWAY_GIT_COMMIT_SHA" "$RAILWAY_GIT_BRANCH" > /out/build.json
# Pre-compress text assets; the debug bundle is tens of MB uncompressed.
RUN find /out -type f \( -name '*.js' -o -name '*.mjs' -o -name '*.json' -o -name '*.wasm' -o -name '*.html' -o -name '*.otf' -o -name '*.ttf' \) -size +1k -exec gzip -9 -k {} \;

FROM node:22-alpine
ENV NODE_ENV=production SITE_DIR=/srv DATA_DIR=/data
WORKDIR /srv
COPY deploy/qa/harness/ /srv/
COPY --from=build /out/ /srv/
COPY deploy/qa/server/server.mjs /opt/qa/server.mjs
CMD ["node", "/opt/qa/server.mjs"]
