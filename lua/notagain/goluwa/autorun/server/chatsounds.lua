util.AddNetworkString("newchatsounds")

net.Receive("newchatsounds", function(len, ply)
	net.Start("newchatsounds")
		net.WriteEntity(ply)
		net.WriteString(net.ReadString())
	net.SendOmit(ply)
end)