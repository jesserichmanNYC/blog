# Hugo: Terra Nillius Blog

Run this command on Docker host

```
docker run -d --name=gaia-blog -p 1313:1313 -e "HUGO_WATCH=true" -e "HUGO_THEME=purehugo" -e "HUGO_BASEURL=http://blog.terranillius.com" alexeiled/hugo
```
