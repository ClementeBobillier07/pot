import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

/// Who the installed agent says is signed in right now. Display only: it never owns historical logs.
public struct DetectedAccount:Sendable,Equatable {
    public var id:String?
    public var email:String?
    /// Plan or subscription label reported by the agent (e.g. "plus", "max").
    public var plan:String?
    /// How the agent is signed in (e.g. "ChatGPT", "claude.ai", "API key").
    public var method:String?
    public var organization:String?
    public init(id:String?=nil,email:String?=nil,plan:String?=nil,method:String?=nil,organization:String?=nil){self.id=id;self.email=email;self.plan=plan;self.method=method;self.organization=organization}
}
public struct AgentDetection:Sendable {
    public var provider:Provider
    public var executable:URL?
    public var version:String?
    public var authenticated:Bool?
    public var account:DetectedAccount?
    public var roots:[URL]
    public var status:String
}

private final class CommandOutput {
    private let lock=NSLock()
    private var data=Data()
    func append(_ chunk:Data){lock.lock();defer{lock.unlock()};if data.count<65536{data.append(chunk.prefix(65536-data.count))}}
    func value()->Data{lock.lock();defer{lock.unlock()};return data}
}
struct CommandResult {var data:Data;var status:Int32;var timedOut:Bool}
enum AgentCommand {
    /// `until` keeps stdin open (some JSON-RPC servers exit on EOF before replying) and stops the
    /// process as soon as the collected output satisfies it.
    static func run(_ executable:URL,_ arguments:[String],input:Data?=nil,timeout:Double=3,until:((Data)->Bool)?=nil)->CommandResult? {
        let p=Process();p.executableURL=executable;p.arguments=arguments
        var environment=ProcessInfo.processInfo.environment
        environment["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"]="1";environment["DISABLE_TELEMETRY"]="1"
        p.environment=environment
        let output=Pipe(),inPipe=Pipe();p.standardOutput=output;p.standardError=output;p.standardInput=inPipe
        let finished=DispatchSemaphore(value:0);p.terminationHandler={_ in finished.signal()}
        do {try p.run()}catch{return nil}
        let buffer=CommandOutput(),drained=DispatchSemaphore(value:0)
        DispatchQueue.global(qos:.utility).async {
            while true {let d=output.fileHandleForReading.availableData;if d.isEmpty{break};buffer.append(d)}
            drained.signal()
        }
        if let input {try? inPipe.fileHandleForWriting.write(contentsOf:input)}
        var timedOut:Bool
        if let until {
            let deadline=Date().addingTimeInterval(timeout)
            var satisfied=false
            while Date()<deadline {
                if until(buffer.value()) {satisfied=true;break}
                if finished.wait(timeout:.now()+0.05) == .success {satisfied=until(buffer.value());break}
            }
            try? inPipe.fileHandleForWriting.close()
            timedOut = !satisfied
            if p.isRunning {p.terminate();if finished.wait(timeout:.now()+0.5) == .timedOut {kill(p.processIdentifier,SIGKILL)}}
        } else {
            try? inPipe.fileHandleForWriting.close()
            timedOut=finished.wait(timeout:.now()+timeout) == .timedOut
        }
        if timedOut && p.isRunning {
            p.terminate()
            if finished.wait(timeout:.now()+0.5) == .timedOut {kill(p.processIdentifier,SIGKILL);_ = finished.wait(timeout:.now()+0.5)}
        }
        _=drained.wait(timeout:.now()+0.5)
        return CommandResult(data:buffer.value(),status:p.isRunning ? -1:p.terminationStatus,timedOut:timedOut)
    }
}

public enum SourceDiscovery {
    public static func defaultRoots(provider:Provider,environment:[String:String]=ProcessInfo.processInfo.environment,home:URL=FileManager.default.homeDirectoryForCurrentUser)->[URL] {
        let fm=FileManager.default
        let candidates:[URL]
        if provider == .codex {
            let base=environment["CODEX_HOME"].map{URL(fileURLWithPath:$0)} ?? home.appendingPathComponent(".codex")
            candidates=[base.appendingPathComponent("sessions"),base.appendingPathComponent("archived_sessions")]
        } else {
            var bases=[home.appendingPathComponent(".claude"),home.appendingPathComponent(".config/claude")]
            if let custom=environment["CLAUDE_CONFIG_DIR"]{bases.insert(URL(fileURLWithPath:custom),at:0)}
            if let xdg=environment["XDG_CONFIG_HOME"]{bases.append(URL(fileURLWithPath:xdg).appendingPathComponent("claude"))}
            candidates=bases.map{$0.appendingPathComponent("projects")}
        }
        var seen=Set<String>()
        return candidates.filter {url in
            var directory:ObjCBool=false
            return fm.fileExists(atPath:url.path,isDirectory:&directory) && directory.boolValue && seen.insert(url.resolvingSymlinksInPath().path).inserted
        }
    }
    /// Run on a background queue. No login, credential reads, token refresh, or agent task is invoked.
    /// Account details use the optional official app-server call; disabled by default because vendor startup behavior is outside Pot's offline control.
    public static func detect(includeAccountDetails:Bool=false)->[AgentDetection] {
        Provider.allCases.map{provider in
            let executable=findExecutable(provider == .codex ? "codex":"claude")
            let roots=defaultRoots(provider:provider)
            guard let executable else{return AgentDetection(provider:provider,executable:nil,version:nil,authenticated:nil,account:nil,roots:roots,status:roots.isEmpty ? "Not found. Choose a log folder or install \(provider.displayName).":"Local logs found; command-line tool not found.")}
            let versionResult=AgentCommand.run(executable,["--version"])
            let version=versionResult.flatMap{String(data:$0.data,encoding:.utf8)}?.split(separator:"\n").last.map(String.init)
            let auth=AgentCommand.run(executable,provider == .codex ? ["login","status"]:["auth","status"])
            var authenticated:Bool?=nil
            var account:DetectedAccount?=nil
            if let auth,!auth.timedOut {
                if provider == .codex {
                    let text=String(data:auth.data,encoding:.utf8) ?? ""
                    if text.localizedCaseInsensitiveContains("not logged in"){authenticated=false}
                    else if text.contains("Logged in") {
                        authenticated=true
                        // "Logged in using ChatGPT" / "Logged in using an API key"
                        let method=text.components(separatedBy:"Logged in using ").dropFirst().first?.split(separator:"\n").first.map{String($0).trimmingCharacters(in:.whitespaces)}
                        account=DetectedAccount(method:method?.replacingOccurrences(of:"an ",with:""))
                    }
                } else if let object=(try? JSONSerialization.jsonObject(with:auth.data)) as? [String:Any] {
                    authenticated=object["loggedIn"] as? Bool ?? (auth.status==0)
                    let email=object["email"] as? String
                    let id=(object["accountId"] as? String).map{"claude:account:"+metricID($0)}
                    if authenticated==true {
                        account=DetectedAccount(id:id,email:email,plan:(object["subscriptionType"] as? String) ?? (object["planTier"] as? String),
                                                method:object["authMethod"] as? String,organization:object["orgName"] as? String)
                    }
                }
            }
            if provider == .codex,includeAccountDetails,let details=readCodexAccount(executable) {
                account=DetectedAccount(id:details.id,email:details.email,plan:details.plan,method:details.method ?? account?.method)
            }
            return AgentDetection(provider:provider,executable:executable,version:version,authenticated:authenticated,account:account,roots:roots,status:roots.isEmpty ? "Installed. No local logs yet; use the agent or choose its log folder.":"Local logs found")
        }
    }
    static func readCodexAccount(_ executable:URL)->DetectedAccount? {
        let requests:[[String:Any]]=[
            ["id":1,"method":"initialize","params":["clientInfo":["name":"pot","version":"0.1.0"],"capabilities":["experimentalApi":false]]],
            ["method":"initialized"],
            ["id":2,"method":"account/read","params":["refreshToken":false]]
        ]
        var data=Data()
        for request in requests {guard let line=try? JSONSerialization.data(withJSONObject:request) else{return nil};data.append(line);data.append(10)}
        guard let result=AgentCommand.run(executable,["app-server","-c","analytics.enabled=false","--stdio"],input:data,timeout:6,until:{accountResponse(in:$0) != nil}) else{return nil}
        return accountResponse(in:result.data)
    }
    /// Parses the JSON-RPC reply to request id 2 (`account/read`).
    static func accountResponse(in data:Data)->DetectedAccount? {
        for line in data.split(separator:10) {
            guard let o=(try? JSONSerialization.jsonObject(with:Data(line))) as? [String:Any],(o["id"] as? Int)==2,let r=o["result"] as? [String:Any],let a=r["account"] as? [String:Any] else{continue}
            let id=(a["id"] as? String).map{"codex:account:"+metricID($0)},email=a["email"] as? String
            let method=(a["type"] as? String).map{$0=="chatgpt" ? "ChatGPT":$0=="apiKey" ? "API key":$0}
            return DetectedAccount(id:id,email:email,plan:a["planType"] as? String,method:method,organization:a["workspaceName"] as? String)
        }
        return nil
    }
    static func findExecutable(_ name:String)->URL? {
        var directories=(ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator:":").map(String.init)
        directories += ["/opt/homebrew/bin","/usr/local/bin",FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path,"/Applications/Codex.app/Contents/Resources"]
        return directories.map{URL(fileURLWithPath:$0).appendingPathComponent(name)}.first{FileManager.default.isExecutableFile(atPath:$0.path)}
    }
}
