# EZ2 Co-op bridge - host side.
# Opens a tunnel to the relay and replays every friend's packets into your local listen server,
# so friends can join with `connect <relay>:<port>` and nobody needs port forwarding.
param(
    [string]$Relay = 'coop.dexx.moe',
    [int]$ControlPort = 27600,
    [int]$GamePort = 27015,
    [string]$Name = $env:USERNAME
)
$ErrorActionPreference = 'Stop'

Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;

public static class Ez2Bridge
{
    const ushort Proto = 1;
    static readonly byte[] Magic = Encoding.ASCII.GetBytes("EZ2B");

    class Peer { public Socket Sock; public DateTime Last; }

    static Socket tunnel;
    static IPEndPoint relayEp, gameEp;
    static IPAddress localIp;

    static bool IsPrivate(IPAddress a)
    {
        byte[] b = a.GetAddressBytes();
        return b[0] == 10 || (b[0] == 172 && b[1] >= 16 && b[1] <= 31) || (b[0] == 192 && b[1] == 168);
    }

    static IPAddress PickLocalAddress(IPAddress relay)
    {
        // The interface Windows would use to reach the relay (normally the LAN card).
        IPAddress outbound = null;
        using (Socket probe = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp))
        {
            try { probe.Connect(relay, 9); outbound = ((IPEndPoint)probe.LocalEndPoint).Address; } catch (SocketException) { }
        }
        if (outbound != null && IsPrivate(outbound)) return outbound;
        foreach (System.Net.NetworkInformation.NetworkInterface ni in System.Net.NetworkInformation.NetworkInterface.GetAllNetworkInterfaces())
        {
            if (ni.OperationalStatus != System.Net.NetworkInformation.OperationalStatus.Up) continue;
            foreach (System.Net.NetworkInformation.UnicastIPAddressInformation ua in ni.GetIPProperties().UnicastAddresses)
                if (ua.Address.AddressFamily == AddressFamily.InterNetwork && IsPrivate(ua.Address)) return ua.Address;
        }
        if (outbound != null) return outbound;
        throw new Exception("No usable network address found (Source ignores 127.0.0.1).");
    }
    static readonly Dictionary<uint, Peer> peers = new Dictionary<uint, Peer>();
    static readonly Dictionary<Socket, uint> bySock = new Dictionary<Socket, uint>();
    public static volatile bool Stop;

    static void Log(string s) { Console.WriteLine(DateTime.Now.ToString("HH:mm:ss") + "  " + s); }

    static void SendCtl(byte op, byte[] body)
    {
        byte[] b = new byte[5 + body.Length];
        Buffer.BlockCopy(Magic, 0, b, 0, 4); b[4] = op;
        Buffer.BlockCopy(body, 0, b, 5, body.Length);
        try { tunnel.SendTo(b, relayEp); } catch (SocketException) { }
    }

    static void DropPeer(uint id)
    {
        Peer p;
        if (!peers.TryGetValue(id, out p)) return;
        bySock.Remove(p.Sock); p.Sock.Close(); peers.Remove(id);
        Log("player link " + id + " closed");
    }

    public static void Run(string relayHost, int controlPort, int gamePort, string name)
    {
        IPAddress ip = null;
        foreach (IPAddress a in Dns.GetHostAddresses(relayHost))
            if (a.AddressFamily == AddressFamily.InterNetwork) { ip = a; break; }
        if (ip == null) throw new Exception("Cannot resolve relay " + relayHost);
        relayEp = new IPEndPoint(ip, controlPort);
        // Source treats datagrams from 127.0.0.1 as its own internal loopback and silently drops them,
        // so talk to the listen server over a real local (preferably private/LAN) address instead.
        localIp = PickLocalAddress(ip);
        gameEp = new IPEndPoint(localIp, gamePort);
        tunnel = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);
        tunnel.Bind(new IPEndPoint(IPAddress.Any, 0));
        // Windows reports ICMP port-unreachable as a recv error on UDP sockets; turn that off.
        const int SIO_UDP_CONNRESET = -1744830452;
        tunnel.IOControl(SIO_UDP_CONNRESET, new byte[] { 0 }, null);

        byte[] nameBytes = Encoding.UTF8.GetBytes(name.Length > 32 ? name.Substring(0, 32) : name);
        byte[] hello = new byte[2 + nameBytes.Length];
        hello[0] = (byte)(Proto & 0xFF); hello[1] = (byte)(Proto >> 8);
        Buffer.BlockCopy(nameBytes, 0, hello, 2, nameBytes.Length);

        int port = 0;
        DateTime lastPing = DateTime.MinValue, lastPong = DateTime.UtcNow, lastHello = DateTime.MinValue;
        byte[] buf = new byte[65536];
        EndPoint from = new IPEndPoint(IPAddress.Any, 0);
        Log("Contacting relay " + relayHost + " (" + relayEp + "), game server at " + gameEp + "...");

        while (!Stop)
        {
            DateTime now = DateTime.UtcNow;
            if (port == 0 && (now - lastHello).TotalSeconds >= 1) { SendCtl(1, hello); lastHello = now; }
            if ((now - lastPing).TotalSeconds >= 2) { SendCtl(3, new byte[0]); lastPing = now; }
            if (port != 0 && (now - lastPong).TotalSeconds > 10)
            {
                Log("Lost the relay - reconnecting...");
                port = 0; lastPong = now;
            }

            List<Socket> read = new List<Socket>();
            read.Add(tunnel);
            foreach (Socket s in bySock.Keys) read.Add(s);
            Socket.Select(read, null, null, 200000);

            foreach (Socket s in read)
            {
                int n;
                try { n = s.ReceiveFrom(buf, ref from); } catch (SocketException) { continue; }
                if (s == tunnel)
                {
                    if (n < 5 || buf[0] != 'E' || buf[1] != 'Z' || buf[2] != '2' || buf[3] != 'B') continue;
                    byte op = buf[4];
                    lastPong = DateTime.UtcNow;
                    if (op == 2 && n >= 7)
                    {
                        int p = buf[5] | (buf[6] << 8);
                        if (p != port)
                        {
                            port = p;
                            Log("");
                            Log("=== BRIDGE READY ===  Friends join from the console with:");
                            Log("      connect " + relayHost + ":" + port);
                            Log("(Keep this window open while you play. Close it to stop the bridge.)");
                            Log("");
                            try { System.Windows.Forms.Clipboard.SetText("connect " + relayHost + ":" + port); Log("(connect command copied to clipboard)"); } catch (Exception) { }
                        }
                    }
                    else if (op == 5 && n >= 9)
                    {
                        uint id = BitConverter.ToUInt32(buf, 5);
                        Peer p;
                        if (!peers.TryGetValue(id, out p))
                        {
                            p = new Peer();
                            p.Sock = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);
                            p.Sock.Bind(new IPEndPoint(localIp, 0));
                            p.Sock.IOControl(SIO_UDP_CONNRESET, new byte[] { 0 }, null);
                            peers[id] = p; bySock[p.Sock] = id;
                            Log("player link " + id + " opened");
                        }
                        p.Last = DateTime.UtcNow;
                        try { p.Sock.SendTo(buf, 9, n - 9, SocketFlags.None, gameEp); } catch (SocketException) { }
                    }
                    else if (op == 6 && n >= 9) DropPeer(BitConverter.ToUInt32(buf, 5));
                    else if (op == 7) { Log("Relay says: " + Encoding.UTF8.GetString(buf, 5, n - 5)); Stop = true; }
                }
                else
                {
                    uint id;
                    if (!bySock.TryGetValue(s, out id)) continue;
                    byte[] pkt = new byte[4 + n];
                    BitConverter.GetBytes(id).CopyTo(pkt, 0);
                    Buffer.BlockCopy(buf, 0, pkt, 4, n);
                    SendCtl(5, pkt);
                }
            }

            List<uint> idle = new List<uint>();
            foreach (KeyValuePair<uint, Peer> kv in peers)
                if ((DateTime.UtcNow - kv.Value.Last).TotalSeconds > 180) idle.Add(kv.Key);
            foreach (uint id in idle) DropPeer(id);
        }
    }
}
'@ -ReferencedAssemblies System.Windows.Forms

$host.UI.RawUI.WindowTitle = 'EZ2 Co-op bridge'
Write-Host "EZ2 Co-op bridge -> relay $Relay (game port $GamePort)"
[Ez2Bridge]::Run($Relay, $ControlPort, $GamePort, $Name)
