import React, { useState, useEffect } from 'react';
import { 
  Shield, 
  AlertTriangle, 
  CheckCircle, 
  FileText, 
  Clock, 
  Users, 
  Search,
  ChevronRight,
  Fingerprint,
  Info,
  History
} from 'lucide-react';

const App = () => {
  const [selectedIssue, setSelectedIssue] = useState(null);
  const [isSigning, setIsSigning] = useState(false);
  const [auditLog, setAuditLog] = useState([
    { id: 1, action: "Policy Updated", target: "0x882A...", actor: "did:verisim:custodian_02", time: "2h ago" },
    { id: 2, action: "Manual Repair", target: "0x441F...", actor: "did:verisim:custodian_01", time: "5h ago" }
  ]);

  const pendingIssues = [
    {
      id: "0x12AB...990F",
      type: "Formal Drift (Contract Breach)",
      modality: "Graph / Semantic",
      severity: "High",
      contract: "CitationContract",
      breach: "Invariant 'claim_validity' failed.",
      cause: "Reference 0x990F... has status 'retracted'.",
      implication: "Approving this update will logically invalidate the authority of the parent Hexad.",
      timestamp: "12 mins ago"
    },
    {
      id: "0xCC21...110E",
      type: "Topological Mutation",
      modality: "Graph",
      severity: "Medium",
      contract: "TaxonomyContract",
      breach: "Edge-addition rate exceeds Poisson threshold (λ=0.05).",
      cause: "Rapid batch update of 450 nodes detected.",
      implication: "Possible systematic bias or archival error in metadata ingestion.",
      timestamp: "45 mins ago"
    }
  ];

  const handleSign = () => {
    setIsSigning(true);
    // Simulate sactify-php + proven ZKP generation
    setTimeout(() => {
      setAuditLog([
        { 
          id: Date.now(), 
          action: "Formal Repair Signed", 
          target: selectedIssue.id, 
          actor: "did:verisim:custodian_01", 
          time: "Just now" 
        },
        ...auditLog
      ]);
      setIsSigning(false);
      setSelectedIssue(null);
    }, 2000);
  };

  return (
    <div className="min-h-screen bg-slate-50 flex flex-col font-sans">
      {/* Header */}
      <nav className="bg-slate-900 text-white p-4 shadow-lg flex justify-between items-center">
        <div className="flex items-center gap-2">
          <Shield className="w-6 h-6 text-blue-400" />
          <span className="font-bold tracking-tight text-lg">VeriSimDB Custodian Portal</span>
        </div>
        <div className="flex items-center gap-4 text-sm">
          <div className="flex items-center gap-2 bg-slate-800 px-3 py-1 rounded-full border border-slate-700">
            <Users className="w-4 h-4 text-slate-400" />
            <span>Quorum: 2/3 Active</span>
          </div>
          <span className="text-slate-400">did:verisim:custodian_01</span>
        </div>
      </nav>

      <main className="flex-grow p-6 grid grid-cols-1 lg:grid-cols-12 gap-6 max-w-[1600px] mx-auto w-full">
        {/* Left: Pending Queue */}
        <div className="lg:col-span-4 flex flex-col gap-4">
          <div className="flex justify-between items-center px-2">
            <h2 className="text-lg font-bold text-slate-800 flex items-center gap-2">
              <Clock className="w-5 h-5 text-orange-500" />
              Pending Reviews
            </h2>
            <span className="bg-orange-100 text-orange-700 text-xs font-bold px-2 py-1 rounded-full">
              {pendingIssues.length} New
            </span>
          </div>

          <div className="space-y-3">
            {pendingIssues.map((issue) => (
              <button
                key={issue.id}
                onClick={() => setSelectedIssue(issue)}
                className={`w-full text-left p-4 rounded-xl border transition-all ${
                  selectedIssue?.id === issue.id 
                  ? 'bg-white border-blue-500 shadow-md ring-2 ring-blue-50' 
                  : 'bg-white border-slate-200 hover:border-slate-300'
                }`}
              >
                <div className="flex justify-between items-start mb-2">
                  <span className="font-mono text-xs text-slate-500">{issue.id}</span>
                  <span className={`text-[10px] font-bold px-2 py-0.5 rounded uppercase ${
                    issue.severity === 'High' ? 'bg-red-100 text-red-700' : 'bg-orange-100 text-orange-700'
                  }`}>
                    {issue.severity}
                  </span>
                </div>
                <h3 className="font-bold text-slate-800 text-sm mb-1">{issue.type}</h3>
                <p className="text-xs text-slate-500 flex items-center gap-1">
                  <FileText className="w-3 h-3" /> {issue.contract}
                </p>
                <div className="mt-3 flex justify-between items-center">
                  <span className="text-[10px] text-slate-400">{issue.timestamp}</span>
                  <ChevronRight className={`w-4 h-4 text-slate-300 ${selectedIssue?.id === issue.id ? 'text-blue-500' : ''}`} />
                </div>
              </button>
            ))}
          </div>
        </div>

        {/* Center: Detailed Evidence (Proven Explainability) */}
        <div className="lg:col-span-5">
          {selectedIssue ? (
            <div className="bg-white rounded-2xl border border-slate-200 shadow-sm overflow-hidden h-full flex flex-col">
              <div className="p-6 border-b border-slate-100 bg-slate-50/50">
                <h2 className="text-xl font-bold text-slate-900 mb-1">Explainability Trace</h2>
                <p className="text-sm text-slate-500 font-mono">Formal Verification Engine (Proven v1.1)</p>
              </div>
              
              <div className="p-6 space-y-6 flex-grow overflow-y-auto">
                <section>
                  <h4 className="text-xs font-bold text-slate-400 uppercase tracking-widest mb-3">Violation Details</h4>
                  <div className="bg-red-50 border border-red-100 p-4 rounded-xl flex gap-3">
                    <AlertTriangle className="w-5 h-5 text-red-500 shrink-0" />
                    <div>
                      <p className="text-sm font-bold text-red-900">{selectedIssue.breach}</p>
                      <p className="text-sm text-red-700 mt-1">{selectedIssue.cause}</p>
                    </div>
                  </div>
                </section>

                <section>
                  <h4 className="text-xs font-bold text-slate-400 uppercase tracking-widest mb-3">Logical Implication</h4>
                  <div className="bg-blue-50 border border-blue-100 p-4 rounded-xl flex gap-3">
                    <Info className="w-5 h-5 text-blue-500 shrink-0" />
                    <p className="text-sm text-blue-900">{selectedIssue.implication}</p>
                  </div>
                </section>

                <section>
                  <h4 className="text-xs font-bold text-slate-400 uppercase tracking-widest mb-3">Proposed Repair</h4>
                  <div className="p-4 border border-slate-200 rounded-xl space-y-3">
                    <p className="text-sm text-slate-600">Revert citation mapping to state <span className="font-mono bg-slate-100 px-1">0x4F2...</span> and append retraction proof to the Temporal Ledger.</p>
                    <div className="flex items-center gap-2 text-xs text-green-600 font-bold bg-green-50 w-fit px-2 py-1 rounded">
                      <CheckCircle className="w-3 h-3" />
                      COHERENCE RESTORED AFTER REPAIR
                    </div>
                  </div>
                </section>
              </div>

              <div className="p-6 bg-slate-50 border-t border-slate-200">
                <button
                  onClick={handleSign}
                  disabled={isSigning}
                  className="w-full bg-slate-900 text-white font-bold py-3 rounded-xl flex items-center justify-center gap-2 hover:bg-slate-800 transition-colors disabled:opacity-50"
                >
                  {isSigning ? (
                    <>
                      <div className="w-5 h-5 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                      Generating ZKP & Signing...
                    </>
                  ) : (
                    <>
                      <Fingerprint className="w-5 h-5" />
                      Sign-Off Repair (Sactify-PHP)
                    </>
                  )}
                </button>
              </div>
            </div>
          ) : (
            <div className="h-full flex flex-col items-center justify-center text-slate-400 border-2 border-dashed border-slate-200 rounded-3xl p-12 text-center">
              <Shield className="w-16 h-16 mb-4 opacity-20" />
              <p>Select a pending issue to review formal drift evidence and authorize repairs.</p>
            </div>
          )}
        </div>

        {/* Right: Audit Log & Stats */}
        <div className="lg:col-span-3 flex flex-col gap-6">
          <div className="bg-white p-6 rounded-2xl border border-slate-200 shadow-sm">
            <h2 className="text-sm font-bold text-slate-800 mb-4 flex items-center gap-2">
              <History className="w-4 h-4 text-blue-500" />
              Recent Activity
            </h2>
            <div className="space-y-4">
              {auditLog.map(log => (
                <div key={log.id} className="text-xs border-l-2 border-slate-100 pl-3 py-1">
                  <p className="font-bold text-slate-700">{log.action}</p>
                  <p className="text-slate-500 mt-1">Target: <span className="font-mono">{log.target}</span></p>
                  <div className="flex justify-between mt-2 text-[10px] text-slate-400">
                    <span>{log.actor.split(':').pop()}</span>
                    <span>{log.time}</span>
                  </div>
                </div>
              ))}
            </div>
          </div>

          <div className="bg-slate-900 p-6 rounded-2xl text-white shadow-lg">
            <h2 className="text-sm font-bold mb-4 flex items-center gap-2 text-blue-400">
              <Activity className="w-4 h-4" />
              Epistemic Health
            </h2>
            <div className="space-y-4">
              <div>
                <div className="flex justify-between text-xs mb-1">
                  <span className="text-slate-400">Formal Coherence</span>
                  <span className="text-green-400">98.2%</span>
                </div>
                <div className="w-full h-1.5 bg-slate-800 rounded-full overflow-hidden">
                  <div className="w-[98%] h-full bg-green-500" />
                </div>
              </div>
              <div>
                <div className="flex justify-between text-xs mb-1">
                  <span className="text-slate-400">Quorums Reached</span>
                  <span className="text-blue-400">24 / 24</span>
                </div>
                <div className="w-full h-1.5 bg-slate-800 rounded-full overflow-hidden">
                  <div className="w-full h-full bg-blue-500" />
                </div>
              </div>
            </div>
          </div>
        </div>
      </main>
    </div>
  );
};

const Activity = ({ className }) => (
  <svg className={className} xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
    <polyline points="22 12 18 12 15 21 9 3 6 12 2 12"></polyline>
  </svg>
);

export default App;
