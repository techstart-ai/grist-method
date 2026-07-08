<!-- GRIST:BEGIN:LOAD — managed by grist-method installer. Do not edit between markers. -->

    <!-- GRIST: prefer YAML over prose if present -->
    <check if="{project-root}/_bmad/custom/grist-schemas/story.grist.yaml exists">
      <action>After locating the story file path, check if a sibling story-S&lt;epic&gt;.&lt;n&gt;.grist.yaml exists in the same directory</action>
      <check if="grist YAML exists">
        <action>Read the YAML file as the primary story spec — it is denser and takes precedence over prose for task/AC data</action>
        <action>Read {project-root}/_bmad/custom/grist-dev-story-emission.md for /grist ship mode rules — apply for the rest of this workflow run</action>
        <note>If YAML and prose disagree, YAML wins. Update YAML state as tasks complete. Do not rewrite prose for state tracking.</note>
        <note>YAML updates use tight style: no comments; flow lists [a, b, c] for scalars; omit empty/null optional keys; one-line scalars ≤200 chars.</note>
      </check>
    </check>

<!-- GRIST:END:LOAD -->
