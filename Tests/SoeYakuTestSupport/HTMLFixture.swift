import Foundation

public enum HTMLFixture {
    public static let html = """
        <!doctype html><html><head><meta charset="utf-8"><title>SoeYaku HTML Reading Fixture</title>
        <style>body { font:20px/1.45 Arial; margin:32px; background:white; color:black; }
        h1 {font-size:28px} h2 {font-size:24px;margin:20px 0 8px} p {margin:8px 0 18px}
        .columns {display:grid; grid-template-columns:1fr 1fr; gap:36px}</style></head><body>
        <nav>Menu and unrelated navigation.</nav><main><h1>Field Notes</h1><div class="columns">
        <div><h2>Forest</h2><p id="left">Maple Observatory records the movement of distant stars throughout the winter, while the night team checks every measurement against the previous survey.</p>
        <p>The forest team measures the young trees every month.</p></div>
        <div><h2>Coast</h2><p id="right">Harbor Laboratory tests rechargeable batteries during repeated heating and cooling cycles, while the safety team monitors the temperature of every sample.</p>
        <p>The coastal team counts the nesting birds every morning.</p></div></div>
        <h2 id="firstResults">Results</h2><p>The forest survey found that young trees grew faster near the northern stream.</p>
        <h2 id="secondResults">Results</h2><p>The coastal survey found that nesting birds preferred the sheltered eastern beach.</p>
        </main></body></html>
        """
}
