import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "finalsRank"

    StyledText {
        text: "Finals Rank"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        text: "Reads the community leaderboard API (api.the-finals-leaderboard.com). Embark publishes one global top 10,000 per board, so ranks here are worldwide, not per-region."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        width: parent.width
        wrapMode: Text.WordWrap
    }

    StyledRect {
        width: parent.width
        height: 1
        color: Theme.surfaceVariant
    }

    StringSetting {
        settingKey: "playerName"
        label: "Player name"
        description: "Your Embark name, or a Steam/PSN/Xbox handle. Add #1234 when the base name is ambiguous."
        placeholder: "YourName#1234"
        defaultValue: ""
    }

    StringSetting {
        settingKey: "board"
        label: "Leaderboard"
        description: "sN + mode, e.g. s12quickcash (Quick Cash), s12powershift, or just s12 for Ranked. Quick Cash starts at s5."
        placeholder: "s12quickcash"
        defaultValue: "s12quickcash"
    }

    SelectionSetting {
        settingKey: "platform"
        label: "Platform"
        description: "crossplay covers every platform at once."
        defaultValue: "crossplay"
        options: ["crossplay", "steam", "psn", "xbox"]
    }

    StyledRect {
        width: parent.width
        height: 1
        color: Theme.surfaceVariant
    }

    StyledText {
        text: "Season"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.DemiBold
        color: Theme.surfaceText
    }

    StyledText {
        text: "There is no public feed for these dates, so they are entered by hand. Update them when Embark announces the next season, or the countdown will read wrong."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        width: parent.width
        wrapMode: Text.WordWrap
    }

    StringSetting {
        settingKey: "seasonName"
        label: "Season name"
        placeholder: "PRIME TIME"
        defaultValue: "PRIME TIME"
    }

    StringSetting {
        settingKey: "seasonStartIso"
        label: "Season start (ISO 8601)"
        description: "UTC. Used only for the progress bar."
        placeholder: "2026-10-20T13:00:00Z"
        defaultValue: "2026-10-20T13:00:00Z"
    }

    StringSetting {
        settingKey: "seasonEndIso"
        label: "Season end (ISO 8601)"
        description: "UTC. Season changes land at 13:00 UTC. The default is an estimate (start + 103 days) until Embark confirms S12's end date."
        placeholder: "2027-01-21T13:00:00Z"
        defaultValue: "2027-01-21T13:00:00Z"
    }

    StyledRect {
        width: parent.width
        height: 1
        color: Theme.surfaceVariant
    }

    StyledText {
        text: "History"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.DemiBold
        color: Theme.surfaceText
    }

    StyledText {
        text: "Records a sample only when your rank or score actually changes, and keeps them in the state directory. The API publishes no history of its own, so every 'since yesterday' figure is built from what this device recorded."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        width: parent.width
        wrapMode: Text.WordWrap
    }

    ToggleSetting {
        settingKey: "historyEnabled"
        label: "Track history"
        description: "Turn off to stop writing and clear nothing already saved."
        defaultValue: true
    }

    SliderSetting {
        settingKey: "retentionDays"
        label: "Keep history for"
        description: "A season runs about 103 days, so 120 covers a full one plus overlap. Older samples are dropped on the next poll."
        defaultValue: 120
        minimum: 7
        maximum: 730
        unit: "days"
        leftIcon: "history"
        rightIcon: "calendar_month"
    }

    ToggleSetting {
        settingKey: "dedupeChanges"
        label: "Only record changes"
        description: "Off logs every poll, which fills the file with identical rows."
        defaultValue: true
    }

    SliderSetting {
        settingKey: "deltaHours"
        label: "Compare movement over"
        description: "Window for the 'since' figure shown in the panel."
        defaultValue: 24
        minimum: 1
        maximum: 168
        unit: "h"
        leftIcon: "timer"
        rightIcon: "hourglass_bottom"
    }

    SliderSetting {
        settingKey: "refreshMinutes"
        label: "Refresh interval"
        description: "How often to re-poll the API. The bar does not need to move fast."
        defaultValue: 15
        minimum: 5
        maximum: 180
        unit: "min"
        leftIcon: "refresh"
        rightIcon: "hourglass_bottom"
    }

    ToggleSetting {
        settingKey: "showCountdown"
        label: "Show countdown on the bar"
        description: "Season time remaining next to the rank."
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "showPoints"
        label: "Show points in the popout"
        description: "Board score for casual modes."
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "showPercentile"
        label: "Show percentile"
        description: "Ranks you as a share of the board — 'top 1.4% of 10,000'. Costs one extra small request per board change."
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "showSeasons"
        label: "Show past seasons"
        description: "Lists your finishing rank in earlier seasons from the community API. These are season-final figures and do not change."
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "includeSponsors"
        label: "Include sponsors boards"
        description: "Off by default. Sponsors boards rank by fan count rather than performance and carry no points, so they are not comparable with the rest."
        defaultValue: false
    }

    ToggleSetting {
        settingKey: "toastOnRankChange"
        label: "Notify on rank change"
        description: "A desktop notification when a poll sees a different rank, measured from the last notification, so it appears in notification history. Fires on the bar pill, not the desktop card."
        defaultValue: true
    }
}