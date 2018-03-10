
_G.webaudio = nil
_G.goluwa = nil
_G.notagain = nil

include("notagain.lua")

notagain.Initialize()
notagain.Autorun()

net.Receive("chatsounds", function() end)
