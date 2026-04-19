
---

## Preliminary Score Assessment — against Sheffield Dissertation Rubric

---

### 1. Report Quality (20%)

**Estimated: 15–17 / 20**

**Strengths:**
- Clear hierarchical structure (5 chapters + appendices), logical narrative arc from motivation to benchmarks
- Professional academic writing — precise technical language, consistent use of defined terminology (e.g., "cluster faults" vs "burst injection")
- Consistent formatting: numbered figures/tables, captions, inline equations with LaTeX notation, cross-references
- Abstract is concise and informative, hitting all four required elements (problem, significance, approach, results)

**Weaknesses / risks:**
- Individual Contribution section is noticeably **longer than 1 page** — rubric explicitly caps it at 1 page; markers may flag this
- Obsidian PDF output formatting (font, line spacing, column layout) may not fully match the required **Times New Roman 12pt, 1.5 line spacing, single column** — this is a document-level risk worth checking before submission

---

### 2. Theory and Literature Review (25%)

**Estimated: 18–20 / 25**

**Strengths:**
- Chapter 2 provides rigorous mathematical foundation for RNS, RRNS, MLD, RS — equations are correct and well-explained
- The comparison of all four ECC families is well-integrated with the project context (Table 2.1 is a clean synthesis)
- The motivation for MLD to resolve Rule 2 ambiguity is clearly argued

**Weaknesses:**
- Only **15 references** in total — too few for a dissertation aiming for the top band; the top band requires "comprehensive literature review with critical assessment of high-quality sources"
- Literature review is **embedded in Chapter 2 rather than being an independent survey** — the rubric treats this as acceptable if discussed with supervisor, but the breadth is narrow (mostly the two core papers [1, 2])
- Limited critical appraisal of alternative approaches (LDPC, Turbo codes, BCH) — Section 1.1 mentions them but dismisses them briefly without deep comparison

---

### 3. Technical Results (25%)

**Estimated: 22–24 / 25**

**Strengths:**
- Implementation scope is impressive: 6 algorithm configurations, all synthesised and tested on physical hardware
- Novel probabilistic fault injection engine (two BRAMs, 100,000-sample BER sweeps) is a genuine engineering contribution
- Parallel vs serial 2NRM-RRNS comparison is the first hardware-quantified result of this kind
- FPGA-MATLAB cross-validation adds rigour and confirms implementation correctness
- All four evaluation dimensions (fault tolerance, latency, resource, storage) are comprehensively covered
- Hardware implementation required resolving 100+ bugs — evidenced by systematic debug logs

**Weaknesses:**
- Power figures are **Vivado estimates, not direct hardware measurement** (acknowledged in text, but limits the strength of the power claims)
- Timing closure only achieved at **50 MHz**, not a higher target frequency — somewhat modest for Artix-7, though justified

---

### 4. Interpretation and Analysis of Results (25%)

**Estimated: 21–23 / 25**

**Strengths:**
- The **LFSR clustering effect** analysis (Section 4.2) is particularly insightful — explains an apparent paradox with original theoretical reasoning
- The explanation of why 3NRM-RRNS is *slower* than C-RRNS-MLD despite the same 84-triplet bound (Section 4.4) demonstrates deep understanding
- Results are consistently linked back to theoretical properties (residue field width → burst tolerance, moduli ordering → candidate count)
- Table 4.5 consolidated comparison and Table 4.6 application scenario recommendations are well-reasoned
- Limitations are explicitly acknowledged (LFSR injection model, exhaustive alignment coverage)

**Weaknesses:**
- The cross-algorithm LFSR clustering caveat is stated cleanly, but the claim that it "does not affect cross-algorithm comparison" is stated rather than rigorously proved — a careful second marker might probe this
- "No observed decoding failures" for C-RRNS-MLD is a strong claim; the caveat is present but brief

---

### 5. ELSEE Context (5%)

**Estimated: 4–5 / 5**

After today's revision, all five dimensions (Economic, Legal/IP, Social/Ethical, Environmental, Safety) are covered with substantive content. Energy figures (0.1 kWh), IP status, open-source licensing, and ethical methodology transparency are all addressed. Clearly meets the "paragraph that meaningfully considers ELSEE" band.

---

## Summary Score

| Criterion | Weight | Estimated Score | Estimated Points |
|-----------|--------|-----------------|-----------------|
| Report Quality | 20% | 15–17 / 20 | 15–17 |
| Theory & Literature Review | 25% | 18–20 / 25 | 18–20 |
| Technical Results | 25% | 22–24 / 25 | 22–24 |
| Interpretation & Analysis | 25% | 21–23 / 25 | 21–23 |
| ELSEE Context | 5% | 4–5 / 5 | 4–5 |
| **Total** | **100%** | — | **80–89 / 100** |

**Central estimate: ~83/100 → High First Class**

---

## Highest-Priority Actions Before Submission

1. **Trim Individual Contribution to ≤1 page** — the rubric is explicit; current version is 2+ pages and risks a formatting penalty
2. **Verify PDF formatting** — check that output matches Times New Roman 12pt, 1.5 line spacing, single column; Obsidian's default CSS may differ
3. **Expand reference list** — adding 5–8 more critically discussed sources would push Theory & Literature from 18 → 20+
4. **Check main body page count** — rubric caps it at 25 pages (excluding abstract, references, appendices); Chapter 1–5 combined should be verified