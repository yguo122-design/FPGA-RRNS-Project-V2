import sys
sys.stdout.reconfigure(encoding='utf-8', errors='replace')
try:
    import fitz
    path = r'd:\FPGAproject\FPGA-RRNS-Project-V2\docs\dissertation\Hardware-Acceleration-for-Cluster-Fault-Tolerance-in-Hybrid-CMOSNon-CMOS-Memories ( dissertation ).pdf'
    doc = fitz.open(path)
    print(f'Pages: {doc.page_count}')
    for i, page in enumerate(doc):
        print(f'=== PAGE {i+1} ===')
        print(page.get_text())
except ImportError:
    try:
        import PyPDF2
        path = r'd:\FPGAproject\FPGA-RRNS-Project-V2\docs\dissertation\Hardware-Acceleration-for-Cluster-Fault-Tolerance-in-Hybrid-CMOSNon-CMOS-Memories ( dissertation ).pdf'
        with open(path, 'rb') as f:
            reader = PyPDF2.PdfReader(f)
            print(f'Pages: {len(reader.pages)}')
            for i, page in enumerate(reader.pages):
                print(f'=== PAGE {i+1} ===')
                print(page.extract_text())
    except ImportError:
        try:
            import pdfplumber
            path = r'd:\FPGAproject\FPGA-RRNS-Project-V2\docs\dissertation\Hardware-Acceleration-for-Cluster-Fault-Tolerance-in-Hybrid-CMOSNon-CMOS-Memories ( dissertation ).pdf'
            with pdfplumber.open(path) as pdf:
                print(f'Pages: {len(pdf.pages)}')
                for i, page in enumerate(pdf.pages):
                    print(f'=== PAGE {i+1} ===')
                    print(page.extract_text())
        except Exception as e:
            print(f'All methods failed: {e}')
except Exception as e:
    print(f'Error: {e}')