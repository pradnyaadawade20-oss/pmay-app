package app

import (
	"net/http"
	"strings"
)

// POST /api/admin/units  {unit_number, building_name, tower, wing, floor, carpet_area, amount}
// Adds a new unit (house) to the inventory. Allowed for super_admin, admin and allotment_manager.
func (s *Server) panelAddUnit(w http.ResponseWriter, r *http.Request) {
	var in struct {
		UnitNumber   string  `json:"unit_number"`
		BuildingName string  `json:"building_name"`
		Tower        string  `json:"tower"`
		Wing         string  `json:"wing"`
		Floor        int     `json:"floor"`
		CarpetArea   float64 `json:"carpet_area"`
		Amount       float64 `json:"amount"`
	}
	if !decode(r, &in) {
		fail(w, 400, "Invalid body")
		return
	}
	in.UnitNumber = strings.TrimSpace(in.UnitNumber)
	in.Tower = strings.TrimSpace(in.Tower)
	in.Wing = strings.TrimSpace(in.Wing)
	in.BuildingName = strings.TrimSpace(in.BuildingName)
	if in.UnitNumber == "" || in.Tower == "" || in.Wing == "" {
		fail(w, 400, "Unit number, tower and wing are required")
		return
	}
	if in.Floor < 0 {
		fail(w, 400, "Floor must be 0 or more")
		return
	}
	if in.Amount <= 0 {
		fail(w, 400, "Price must be greater than 0")
		return
	}
	_, err := s.db.ExecContext(r.Context(),
		`INSERT INTO units (unit_number,wing,tower,floor,building_name,carpet_area_sqm,rera_carpet_area,consideration_amount)
		 VALUES ($1,$2,$3,$4,NULLIF($5,''),$6,$6,$7)`,
		in.UnitNumber, in.Wing, in.Tower, in.Floor, in.BuildingName, in.CarpetArea, in.Amount)
	if err != nil {
		if strings.Contains(err.Error(), "duplicate key") {
			fail(w, 409, "Unit "+in.UnitNumber+" already exists")
			return
		}
		fail(w, 500, "DB error")
		return
	}
	writeJSON(w, 200, M{"success": true})
}