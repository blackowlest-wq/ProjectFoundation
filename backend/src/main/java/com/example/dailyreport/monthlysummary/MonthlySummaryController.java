/**
 * 管理者向け月次集計API Controller。
 */
package com.example.dailyreport.monthlysummary;

import com.example.dailyreport.auth.AuthenticatedUser;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/monthly-summaries")
public class MonthlySummaryController {
    private final MonthlySummaryService service;

    public MonthlySummaryController(MonthlySummaryService service) {
        this.service = service;
    }

    @GetMapping
    public MonthlySummaryResponse monthlySummary(@RequestParam(required = false) String yearMonth,
                                                  @AuthenticationPrincipal AuthenticatedUser principal) {
        return service.get(yearMonth, principal);
    }
}
