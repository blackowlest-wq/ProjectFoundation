/**
 * 利用者テーブルに対応するEntity。
 * 認証情報に加えて、日報作成時に必要な所属・休憩区分・勤務区分の設定も保持する。
 */
package com.example.dailyreport.auth;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

@Entity
@Table(name = "users")
public class AppUser {
    @Id
    @Column(name = "user_id", length = 20)
    private String userId;

    @Column(name = "employee_id", nullable = false, unique = true, length = 20)
    private String employeeId;

    @Column(name = "login_id", nullable = false, unique = true, length = 80)
    private String loginId;

    @Column(name = "password_hash", nullable = false, length = 100)
    private String passwordHash;

    @Column(name = "user_name", nullable = false, length = 120)
    private String userName;

    @Enumerated(EnumType.STRING)
    @Column(name = "user_role", nullable = false, length = 20)
    private Role role;

    @Column(name = "group_id", length = 20)
    private String groupId;

    @Column(name = "group_name", length = 120)
    private String groupName;

    @Column(name = "break_type_id", length = 20)
    private String breakTypeId;

    @Column(name = "break_type_name", length = 120)
    private String breakTypeName;

    @Column(name = "work_time_type_id", length = 20)
    private String workTimeTypeId;

    @Column(name = "work_time_type_name", length = 120)
    private String workTimeTypeName;

    protected AppUser() {
    }

    public AppUser(String userId, String employeeId, String loginId, String passwordHash, String userName,
                   Role role, String groupId, String groupName, String breakTypeId, String breakTypeName,
                   String workTimeTypeId, String workTimeTypeName) {
        this.userId = userId;
        this.employeeId = employeeId;
        this.loginId = loginId;
        this.passwordHash = passwordHash;
        this.userName = userName;
        this.role = role;
        this.groupId = groupId;
        this.groupName = groupName;
        this.breakTypeId = breakTypeId;
        this.breakTypeName = breakTypeName;
        this.workTimeTypeId = workTimeTypeId;
        this.workTimeTypeName = workTimeTypeName;
    }

    public String getUserId() { return userId; }
    public String getEmployeeId() { return employeeId; }
    public String getLoginId() { return loginId; }
    public String getPasswordHash() { return passwordHash; }
    public String getUserName() { return userName; }
    public Role getRole() { return role; }
    public String getGroupId() { return groupId; }
    public String getGroupName() { return groupName; }
    public String getBreakTypeId() { return breakTypeId; }
    public String getBreakTypeName() { return breakTypeName; }
    public String getWorkTimeTypeId() { return workTimeTypeId; }
    public String getWorkTimeTypeName() { return workTimeTypeName; }
}
