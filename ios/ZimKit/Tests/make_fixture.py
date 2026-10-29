import sys
from libzim.writer import Creator, Item, StringProvider, Hint
class P(Item):
    def __init__(s,path,title,mime,content,front=True): s.p,s.t,s.m,s.c,s.f=path,title,mime,content,front
    def get_path(s): return s.p
    def get_title(s): return s.t
    def get_mimetype(s): return s.m
    def get_contentprovider(s): return StringProvider(s.c)
    def get_hints(s): return {Hint.FRONT_ARTICLE: s.f, Hint.COMPRESS: True}
with Creator(sys.argv[1]).config_indexing(False, "eng") as c:
    c.set_mainpath("Home")
    for k,v in {"Title":"NOMAD Test","Language":"eng","Creator":"NOMAD","Publisher":"NOMAD","Date":"2026-10-29","Description":"Fixture","Name":"nomad_test"}.items():
        c.add_metadata(k,v)
    c.add_item(P("Home","Home page","text/html",'<html><body><h1>Home</h1><a href="Water_purification">Water</a><img src="img/dot.svg"></body></html>'))
    c.add_item(P("Water_purification","Water purification","text/html","<html><body><p>Boil water for one minute.</p></body></html>"))
    c.add_item(P("Wound_care","Wound care","text/html","<html><body><p>Clean the wound.</p></body></html>"))
    c.add_item(P("img/dot.svg","dot.svg","image/svg+xml",'<svg xmlns="http://www.w3.org/2000/svg"/>',False))
    c.add_redirection("Water","Water (redirect)","Water_purification",{Hint.FRONT_ARTICLE: False})
