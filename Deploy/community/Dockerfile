FROM python:3.12-slim
WORKDIR /app
COPY Tools/PluginCommunity /app/Tools/PluginCommunity
COPY Resources/Plugins /app/Resources/Plugins
COPY Packages/PhotoDomain/Sources/Resources/edit-recipe.schema.json /app/Packages/PhotoDomain/Sources/Resources/edit-recipe.schema.json
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 LUMA_COMMUNITY_BIND=0.0.0.0 LUMA_COMMUNITY_DATA=/data/community.sqlite3
USER 10001:10001
EXPOSE 8791
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8791/ready',timeout=2)"
CMD ["python","Tools/PluginCommunity/server.py","--seed-examples"]
