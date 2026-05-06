<!-- GRIST:BEGIN:COMPLETE — managed by grist-method installer. Do not edit between markers. -->

    <!-- GRIST: update YAML state instead of prose -->
    <check if="story YAML file exists (story-S&lt;n&gt;.&lt;m&gt;.grist.yaml)">
      <action>Set story YAML `status: in-review`</action>
      <action>Append one-liner per completed task to YAML `notes:` field</action>
      <action>Append newly created/modified file paths to YAML `files:` list (op: modify)</action>
      <note>Do not rewrite the prose story file for state tracking — YAML is the state store.</note>
    </check>

<!-- GRIST:END:COMPLETE -->
