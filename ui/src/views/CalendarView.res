// SPDX-License-Identifier: PMPL-1.0-or-later
// Calendar View

open Types

type calendarView = Month | Week | Day

type calendarEvent = {
  row: row,
  date: Date.t,
  title: string,
}

module DateUtils = {
  let getMonthStart = (date: Date.t): Date.t => {
    let year = date->Date.getFullYear
    let month = date->Date.getMonth
    %raw(`new Date(year, month, 1)`)
  }

  let getMonthEnd = (date: Date.t): Date.t => {
    let year = date->Date.getFullYear
    let month = date->Date.getMonth
    %raw(`new Date(year, month + 1, 0)`)
  }

  let getWeekStart = (date: Date.t): Date.t => {
    let dayOfWeek = date->Date.getDay
    let diff = dayOfWeek
    Date.fromTime(date->Date.getTime -. Float.fromInt(diff) *. 86400000.0)
  }

  let getDaysInMonth = (date: Date.t): int => {
    getMonthEnd(date)->Date.getDate
  }

  let isSameDay = (date1: Date.t, date2: Date.t): bool => {
    date1->Date.getFullYear == date2->Date.getFullYear &&
    date1->Date.getMonth == date2->Date.getMonth &&
    date1->Date.getDate == date2->Date.getDate
  }

  let formatMonthYear = (date: Date.t): string => {
    let months = [
      "January",
      "February",
      "March",
      "April",
      "May",
      "June",
      "July",
      "August",
      "September",
      "October",
      "November",
      "December",
    ]
    let month = months->Array.get(date->Date.getMonth)->Option.getOr("")
    let year = date->Date.getFullYear->Int.toString
    `${month} ${year}`
  }

  let formatDate = (date: Date.t): string => {
    let year = date->Date.getFullYear->Int.toString
    let month = (date->Date.getMonth + 1)->Int.toString->String.padStart(2, "0")
    let day = date->Date.getDate->Int.toString->String.padStart(2, "0")
    `${year}-${month}-${day}`
  }
}

@react.component
let make = (
  ~tableId: string,
  ~dateFieldId: string,
  ~rows: array<row>,
  ~fields: array<fieldConfig>,
  ~onEventClick: option<row => unit>=?,
) => {
  let (currentDate, setCurrentDate) = React.useState(() => Date.make())
  let (viewMode, setViewMode) = React.useState(() => Month)

  // Get primary field for event titles
  let primaryField = fields->Array.find(f => f.name == "Title" || f.name == "Name")
  let primaryFieldId = switch primaryField {
  | Some(f) => f.id
  | None => fields->Array.get(0)->Option.mapOr("", f => f.id)
  }

  // Convert rows to calendar events
  let events = rows->Array.filterMap(row => {
    switch row.cells->Dict.get(dateFieldId) {
    | Some({value: DateValue(date)}) => {
        let title = switch row.cells->Dict.get(primaryFieldId) {
        | Some({value: TextValue(text)}) => text
        | _ => `Event ${row.id}`
        }
        Some({row, date, title})
      }
    | _ => None
    }
  })

  // Navigation
  let goToPreviousMonth = () => {
    setCurrentDate(prev => {
      let year = prev->Date.getFullYear
      let month = prev->Date.getMonth
      %raw(`new Date(year, month - 1, 1)`)
    })
  }

  let goToNextMonth = () => {
    setCurrentDate(prev => {
      let year = prev->Date.getFullYear
      let month = prev->Date.getMonth
      %raw(`new Date(year, month + 1, 1)`)
    })
  }

  let goToToday = () => {
    setCurrentDate(_ => Date.make())
  }

  // Get events for a specific day
  let getEventsForDay = (day: Date.t): array<calendarEvent> => {
    events->Array.filter(event => DateUtils.isSameDay(event.date, day))
  }

  // Render month view
  let renderMonthView = () => {
    let monthStart = DateUtils.getMonthStart(currentDate)
    let monthEnd = DateUtils.getMonthEnd(currentDate)
    let daysInMonth = DateUtils.getDaysInMonth(currentDate)

    // Get the starting day of week for the month (0 = Sunday)
    let startDayOfWeek = monthStart->Date.getDay

    // Calculate total cells needed (previous month padding + current month + next month padding)
    let totalCells = Int.fromFloat(%raw(`Math.ceil((startDayOfWeek + daysInMonth) / 7) * 7`))

    let cells = Array.fromInitializer(~length=totalCells, i => {
      let dayNumber = i - startDayOfWeek + 1

      if dayNumber < 1 || dayNumber > daysInMonth {
        // Empty cell for previous/next month
        <div key={Int.toString(i)} className="calendar-day calendar-day-other-month" />
      } else {
        let year = currentDate->Date.getFullYear
        let month = currentDate->Date.getMonth
        let cellDate = %raw(`new Date(year, month, dayNumber)`)
        let dayEvents = getEventsForDay(cellDate)
        let isToday = DateUtils.isSameDay(cellDate, Date.make())

        <div
          key={Int.toString(i)} className={`calendar-day ${isToday ? "calendar-day-today" : ""}`}
        >
          <div className="calendar-day-number"> {React.string(Int.toString(dayNumber))} </div>
          <div className="calendar-day-events">
            {dayEvents
            ->Array.slice(~start=0, ~end=3)
            ->Array.map(event => {
              <div
                key={event.row.id}
                className="calendar-event"
                onClick={_ => {
                  switch onEventClick {
                  | Some(handler) => handler(event.row)
                  | None => ()
                  }
                }}
              >
                <div className="calendar-event-title"> {React.string(event.title)} </div>
              </div>
            })
            ->React.array}
            {if dayEvents->Array.length > 3 {
              <div className="calendar-event-more">
                {React.string(`+${Int.toString(dayEvents->Array.length - 3)} more`)}
              </div>
            } else {
              React.null
            }}
          </div>
        </div>
      }
    })

    <div className="calendar-month-grid">
      <div className="calendar-weekday-headers">
        {["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        ->Array.map(day => {
          <div key={day} className="calendar-weekday-header"> {React.string(day)} </div>
        })
        ->React.array}
      </div>
      <div className="calendar-days-grid"> {cells->React.array} </div>
    </div>
  }

  // Render week view (simplified for now)
  let renderWeekView = () => {
    <div className="calendar-week-view">
      <p> {React.string("Week view - Coming soon")} </p>
    </div>
  }

  // Render day view (simplified for now)
  let renderDayView = () => {
    <div className="calendar-day-view">
      <p> {React.string("Day view - Coming soon")} </p>
    </div>
  }

  <div className="calendar-view">
    <div className="calendar-header">
      <div className="calendar-nav">
        <button className="calendar-nav-button" onClick={_ => goToPreviousMonth()}>
          {React.string("‹")}
        </button>
        <button className="calendar-today-button" onClick={_ => goToToday()}>
          {React.string("Today")}
        </button>
        <button className="calendar-nav-button" onClick={_ => goToNextMonth()}>
          {React.string("›")}
        </button>
      </div>
      <div className="calendar-title"> {React.string(DateUtils.formatMonthYear(currentDate))} </div>
      <div className="calendar-view-switcher">
        <button
          className={`calendar-view-button ${viewMode == Month ? "active" : ""}`}
          onClick={_ => setViewMode(_ => Month)}
        >
          {React.string("Month")}
        </button>
        <button
          className={`calendar-view-button ${viewMode == Week ? "active" : ""}`}
          onClick={_ => setViewMode(_ => Week)}
        >
          {React.string("Week")}
        </button>
        <button
          className={`calendar-view-button ${viewMode == Day ? "active" : ""}`}
          onClick={_ => setViewMode(_ => Day)}
        >
          {React.string("Day")}
        </button>
      </div>
    </div>

    <div className="calendar-body">
      {switch viewMode {
      | Month => renderMonthView()
      | Week => renderWeekView()
      | Day => renderDayView()
      }}
    </div>
  </div>
}
